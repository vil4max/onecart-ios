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
    case loadFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .storeNotLoaded(scope):
            String(localized: "sync.store_not_loaded \(scope.rawValue)")
        case let .unableToIdentifyStore(url):
            String(
                localized: "sync.store_unidentified \(url?.lastPathComponent ?? String(localized: "sync.store_no_url"))"
            )
        case let .loadFailed(underlying):
            underlying.localizedDescription
        }
    }
}

final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    static let cloudKitContainerIdentifier = "iCloud.com.vil555tim.onecart"

    var container: NSPersistentCloudKitContainer
    let inMemory: Bool

    var privateStore: NSPersistentStore?
    var sharedStore: NSPersistentStore?

    var isLoaded: Bool {
        loadLock.lock()
        defer { loadLock.unlock() }
        return loaded
    }

    let logger = Logger(
        subsystem: "com.vil555tim.onecart",
        category: "Persistence"
    )
    let loadLock = NSLock()
    var loaded = false
    var loading = false
    var loadWaiters: [CheckedContinuation<Result<Void, Error>, Never>] = []
    let storeDirectoryURL: URL
    let cloudKitEnabled: Bool

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
                .appendingPathComponent("OneCartInMemory-\(UUID().uuidString)", isDirectory: true)
                : NSPersistentContainer.defaultDirectoryURL())

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

        container = Self.makeContainer()
        container.persistentStoreDescriptions = Self.makeStoreDescriptions(
            directory: self.storeDirectoryURL,
            inMemory: inMemory,
            cloudKitEnabled: cloudKitEnabled
        )
    }

    static let cloudKitLocalEnvironmentKey = "onecart.cloudkit-local-environment"

    func load() async throws {
        if isLoaded {
            return
        }

        do {
            try reconcileCloudKitEnvironmentBeforeLoad()
            try await loadPersistentStoresOnce()
            stampCloudKitEnvironmentAfterSuccessfulLoad()
        } catch {
            logger.error(
                "Persistent store load failed; preserving store files: \(error.localizedDescription, privacy: .public)"
            )
            throw PersistenceError.loadFailed(underlying: error)
        }
    }

    @discardableResult
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
        guard !objectID.isTemporaryID else { return nil }
        guard let store = objectID.persistentStore else { return nil }
        if let byURL = Self.scope(forStoreURL: store.url) {
            return byURL
        }
        if let privateStore, store === privateStore {
            return .private
        }
        if let sharedStore, store === sharedStore {
            return .shared
        }
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
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.acceptShareInvitationsWithoutTimeout(
                    metadata,
                    into: sharedStore
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 22_000_000_000)
                throw OneCartCloudKitError.shareTimedOut
            }
            do {
                try await group.next()!
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func acceptShareInvitationsWithoutTimeout(
        _ metadata: [CKShare.Metadata],
        into sharedStore: NSPersistentStore
    ) async throws {
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Void, Error>
        ) in
            let lock = NSLock()
            var resumed = false
            container.acceptShareInvitations(from: metadata, into: sharedStore) { _, error in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
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
        if error is CKError {
            return false
        }
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain {
            return false
        }
        if CloudKitUserFacingError.isProductionSchemaFailure(error) {
            return false
        }
        let text = nsError.localizedDescription.lowercased()
        if text.contains("mirroring delegate")
            || text.contains("production schema")
            || text.contains("cannot create or modify field")
            || text.contains("ckerror")
            || text.contains("partial failure")
        {
            return false
        }
        if nsError.domain == NSCocoaErrorDomain {
            return true
        }
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
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        context.shouldDeleteInaccessibleFaults = true
    }
}
