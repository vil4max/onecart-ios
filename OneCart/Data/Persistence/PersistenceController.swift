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
        case let .storeNotLoaded(scope):
            "Хранилище \(scope.rawValue) ещё не загружено."
        case let .unableToIdentifyStore(url):
            "Не удалось определить Core Data store: \(url?.lastPathComponent ?? "без URL")."
        }
    }
}

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    static let cloudKitContainerIdentifier = "iCloud.com.vil555tim.onecart"

    private(set) var container: NSPersistentCloudKitContainer
    let inMemory: Bool

    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?

    var isLoaded: Bool {
        loadLock.lock()
        defer { loadLock.unlock() }
        return loaded
    }

    private let logger = Logger(
        subsystem: "com.vil555tim.onecart",
        category: "Persistence"
    )
    private let loadLock = NSLock()
    private var loaded = false
    private var loading = false
    private var loadWaiters: [CheckedContinuation<Result<Void, Error>, Never>] = []
    private let storeDirectoryURL: URL
    private let cloudKitEnabled: Bool

    init(
        inMemory: Bool = false,
        storeDirectoryURL: URL? = nil,
        cloudKitEnabled: Bool = true
    ) {
        self.inMemory = inMemory
        self.cloudKitEnabled = cloudKitEnabled
        self.storeDirectoryURL = storeDirectoryURL
            ?? (inMemory
                ? FileManager.default.temporaryDirectory
                : NSPersistentContainer.defaultDirectoryURL())

        if !inMemory {
            do {
                try FileManager.default.createDirectory(
                    at: self.storeDirectoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                logger.error(
                    "Unable to create persistent store directory: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        container = Self.makeContainer()
        container.persistentStoreDescriptions = Self.makeStoreDescriptions(
            directory: self.storeDirectoryURL,
            inMemory: inMemory,
            cloudKitEnabled: cloudKitEnabled
        )
    }

    func load() async throws {
        if isLoaded {
            return
        }

        do {
            try await loadPersistentStoresOnce()
        } catch {
            guard !inMemory else { throw error }
            logger.error(
                "Persistent store load failed; rebuilding stores: \(error.localizedDescription, privacy: .public)"
            )
            try hardResetPersistentStores()
            try await loadPersistentStoresOnce()
        }
    }

    func hardResetPersistentStores() throws {
        guard !inMemory else { return }

        loadLock.lock()
        loaded = false
        loading = false
        privateStore = nil
        sharedStore = nil
        let waiters = loadWaiters
        loadWaiters.removeAll()
        loadLock.unlock()
        waiters.forEach { $0.resume(returning: .failure(PersistenceError.storeNotLoaded(.private))) }

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            if let url = store.url {
                try? coordinator.destroyPersistentStore(at: url, ofType: store.type, options: nil)
            } else {
                try? coordinator.remove(store)
            }
        }

        Self.removeAllOneCartStoreFiles(in: storeDirectoryURL)

        container = Self.makeContainer()
        container.persistentStoreDescriptions = Self.makeStoreDescriptions(
            directory: storeDirectoryURL,
            inMemory: false,
            cloudKitEnabled: cloudKitEnabled
        )
    }

    func resetLocalStoreFiles() throws {
        try hardResetPersistentStores()
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
        try context.assign(object, to: store(for: scope))
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

    private func loadPersistentStoresOnce() async throws {
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

                loadLock.lock()
                callbackCount += 1
                if let error, firstError == nil {
                    firstError = error
                }
                let isFinished = callbackCount == expectedCount
                loadLock.unlock()

                if let error {
                    logger.error(
                        "Failed loading \(description.url?.lastPathComponent ?? "store", privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    logger.info(
                        "Loaded \(description.url?.lastPathComponent ?? "store", privacy: .public)"
                    )
                }

                guard isFinished else { return }
                finishLoading(firstError: firstError)
            }
        }

        try result.get()
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

    static func isUserFacingCoreDataFailure(_ error: Error) -> Bool {
        // CloudKit / network failures must not be treated as corrupt local stores
        // (Welcome Retry only hard-resets on true Core Data failures).
        if error is CKError {
            return false
        }
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain {
            return false
        }
        if nsError.domain == NSCocoaErrorDomain {
            return true
        }
        let text = nsError.localizedDescription.lowercased()
        return text.contains("core data")
            || text.contains("incompatible")
            || text.contains("migration")
            || text.contains("unique constraint")
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

    private static func makeContainer() -> NSPersistentCloudKitContainer {
        let model = OneCartManagedObjectModel.makeModel()
        return NSPersistentCloudKitContainer(name: "OneCart", managedObjectModel: model)
    }

    private static func makeStoreDescriptions(
        directory: URL,
        inMemory: Bool,
        cloudKitEnabled: Bool
    ) -> [NSPersistentStoreDescription] {
        [
            makeStoreDescription(
                scope: .private,
                directory: directory,
                inMemory: inMemory,
                cloudKitEnabled: cloudKitEnabled
            ),
            makeStoreDescription(
                scope: .shared,
                directory: directory,
                inMemory: inMemory,
                cloudKitEnabled: cloudKitEnabled
            ),
        ]
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
            description.shouldAddStoreAsynchronously = false
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

    private static func removeAllOneCartStoreFiles(in directory: URL) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents {
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix("onecart-") else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private static func scope(forStoreURL url: URL?) -> PersistentStoreScope? {
        guard let name = url?.lastPathComponent.lowercased() else { return nil }
        if name.contains("private") { return .private }
        if name.contains("shared") { return .shared }
        return nil
    }
}
