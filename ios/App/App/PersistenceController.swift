import CloudKit
import CoreData
import Foundation
import os.log

enum PersistentStoreScope: String {
    case `private`
    case shared
}

enum PersistenceError: LocalizedError {
    case storeNotLoaded(PersistentStoreScope)
    case unableToIdentifyStore(URL?)

    var errorDescription: String? {
        switch self {
        case .storeNotLoaded(let scope):
            return "Хранилище \(scope.rawValue) ещё не загружено."
        case .unableToIdentifyStore(let url):
            return "Не удалось определить Core Data store: \(url?.lastPathComponent ?? "без URL")."
        }
    }
}

final class PersistenceController {
    static let shared = PersistenceController()

    static let cloudKitContainerIdentifier = "iCloud.com.vil555tim.onecart"

    let container: NSPersistentCloudKitContainer
    let inMemory: Bool

    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    private let logger = Logger(
        subsystem: "com.vil55tim.onecart",
        category: "Persistence"
    )
    private let loadLock = NSLock()
    private var loaded = false
    private var loading = false
    private var loadWaiters: [CheckedContinuation<Result<Void, Error>, Never>] = []

    init(
        inMemory: Bool = false,
        storeDirectoryURL: URL? = nil,
        cloudKitEnabled: Bool = true
    ) {
        self.inMemory = inMemory

        let model = OneCartManagedObjectModel.makeModel()
        container = NSPersistentCloudKitContainer(name: "OneCart", managedObjectModel: model)

        let directory = storeDirectoryURL
            ?? (inMemory
                ? FileManager.default.temporaryDirectory
                : NSPersistentContainer.defaultDirectoryURL())
        if !inMemory {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                logger.error("Unable to create persistent store directory: \(error.localizedDescription, privacy: .public)")
            }
        }

        let privateDescription = Self.makeStoreDescription(
            scope: .private,
            directory: directory,
            inMemory: inMemory,
            cloudKitEnabled: cloudKitEnabled
        )
        let sharedDescription = Self.makeStoreDescription(
            scope: .shared,
            directory: directory,
            inMemory: inMemory,
            cloudKitEnabled: cloudKitEnabled
        )
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
    }

    func load() async throws {
        if loaded {
            return
        }

        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            loadLock.lock()
            if loaded {
                loadLock.unlock()
                continuation.resume(returning: .success(()))
                return
            }

            loadWaiters.append(continuation)
            if loading {
                loadLock.unlock()
                return
            }
            loading = true
            loadLock.unlock()

            var callbackCount = 0
            var firstError: Error?
            let expectedCount = self.container.persistentStoreDescriptions.count

            self.container.loadPersistentStores { [weak self] description, error in
                guard let self else { return }

                self.loadLock.lock()
                callbackCount += 1
                if let error, firstError == nil {
                    firstError = error
                }
                let isFinished = callbackCount == expectedCount
                self.loadLock.unlock()

                if let error {
                    self.logger.error(
                        "Failed loading \(description.url?.lastPathComponent ?? "store", privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    self.logger.info(
                        "Loaded \(description.url?.lastPathComponent ?? "store", privacy: .public)"
                    )
                }

                guard isFinished else { return }
                self.finishLoading(firstError: firstError)
            }
        }

        try result.get()
    }

    func store(for scope: PersistentStoreScope) throws -> NSPersistentStore {
        switch scope {
        case .private:
            guard let privateStore else { throw PersistenceError.storeNotLoaded(.private) }
            return privateStore
        case .shared:
            guard let sharedStore else { throw PersistenceError.storeNotLoaded(.shared) }
            return sharedStore
        }
    }

    func scope(for objectID: NSManagedObjectID) -> PersistentStoreScope? {
        guard let store = objectID.persistentStore else { return nil }
        if store == privateStore { return .private }
        if store == sharedStore { return .shared }
        return nil
    }

    func scope(for object: NSManagedObject) -> PersistentStoreScope? {
        scope(for: object.objectID)
    }

    func assign(
        _ object: NSManagedObject,
        to scope: PersistentStoreScope,
        in context: NSManagedObjectContext
    ) throws {
        context.assign(object, to: try store(for: scope))
    }

    func assign(
        _ object: NSManagedObject,
        toSameStoreAs root: NSManagedObject,
        in context: NSManagedObjectContext
    ) throws {
        guard let store = root.objectID.persistentStore else {
            throw PersistenceError.unableToIdentifyStore(root.objectID.persistentStore?.url)
        }
        context.assign(object, to: store)
    }

    func newBackgroundContext(author: String = "OneCartRepository") -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.name = author
        context.transactionAuthor = author
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    func performBackgroundTask<T>(
        author: String = "OneCartRepository",
        _ block: @escaping (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let context = newBackgroundContext(author: author)
            context.perform {
                do {
                    let value = try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: value)
                } catch {
                    context.rollback()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func acceptShareInvitations(from metadata: [CKShare.Metadata]) async throws {
        guard !inMemory else { return }
        let sharedStore = try store(for: .shared)
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Void, Error>
        ) in
            container.acceptShareInvitations(from: metadata, into: sharedStore) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func finishLoading(firstError: Error?) {
        loadLock.lock()
        defer { loadLock.unlock() }

        let result: Result<Void, Error>
        if let firstError {
            result = .failure(firstError)
        } else {
            do {
                try identifyStores()
                configureContexts()
                loaded = true
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }

        loading = false
        let waiters = loadWaiters
        loadWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }

    private func identifyStores() throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            switch Self.scope(forStoreURL: store.url) {
            case .private:
                privateStore = store
            case .shared:
                sharedStore = store
            case nil:
                throw PersistenceError.unableToIdentifyStore(store.url)
            }
        }

        guard privateStore != nil else { throw PersistenceError.storeNotLoaded(.private) }
        guard sharedStore != nil else { throw PersistenceError.storeNotLoaded(.shared) }
    }

    private func configureContexts() {
        let context = container.viewContext
        context.name = "OneCartViewContext"
        context.transactionAuthor = "OneCartUI"
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.shouldDeleteInaccessibleFaults = true
    }

    private static func makeStoreDescription(
        scope: PersistentStoreScope,
        directory: URL,
        inMemory: Bool,
        cloudKitEnabled: Bool
    ) -> NSPersistentStoreDescription {
        let fileName = scope == .private ? "OneCart-private.sqlite" : "OneCart-shared.sqlite"
        let description: NSPersistentStoreDescription

        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null/\(fileName)")
            description.shouldAddStoreAsynchronously = false
        } else {
            description = NSPersistentStoreDescription(
                url: directory.appendingPathComponent(fileName)
            )
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = true
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true

            if cloudKitEnabled {
                let cloudKitOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: cloudKitContainerIdentifier
                )
                cloudKitOptions.databaseScope = scope == .private ? .private : .shared
                description.cloudKitContainerOptions = cloudKitOptions
            }
        }

        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        return description
    }

    private static func scope(forStoreURL url: URL?) -> PersistentStoreScope? {
        guard let name = url?.lastPathComponent.lowercased() else { return nil }
        if name.contains("private") { return .private }
        if name.contains("shared") { return .shared }
        return nil
    }
}
