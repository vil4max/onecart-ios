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

/// `@unchecked Sendable`: every mutable field is guarded by a lock. `storeLock` guards the
/// container and the store references, which background contexts read while account deletion
/// or a hard reset swaps them; `loadLock` guards the load and deletion flags and the waiters.
/// `storeLock` is never held while taking `loadLock`, and finishLoading takes it inside `loadLock`.
final class PersistenceController: @unchecked Sendable {
    static let shared = PersistenceController()

    static let cloudKitContainerIdentifier = "iCloud.com.vil555tim.onecart"

    private let storeLock = NSLock()
    private var lockedContainer: NSPersistentCloudKitContainer
    private var lockedPrivateStore: NSPersistentStore?
    private var lockedSharedStore: NSPersistentStore?

    var container: NSPersistentCloudKitContainer {
        get { storeLock.withLock { lockedContainer } }
        set { storeLock.withLock { lockedContainer = newValue } }
    }

    var privateStore: NSPersistentStore? {
        get { storeLock.withLock { lockedPrivateStore } }
        set { storeLock.withLock { lockedPrivateStore = newValue } }
    }

    var sharedStore: NSPersistentStore? {
        get { storeLock.withLock { lockedSharedStore } }
        set { storeLock.withLock { lockedSharedStore = newValue } }
    }

    let isEphemeral: Bool

    var isLoaded: Bool {
        loadLock.lock()
        defer { loadLock.unlock() }
        return loaded
    }

    let logger = Logger(
        subsystem: OneCartLog.subsystem,
        category: "Persistence"
    )
    let loadLock = NSLock()
    var loaded = false
    var loading = false
    var accountDeletionInProgress = false
    var loadWaiters: [CheckedContinuation<Result<Void, Error>, Never>] = []
    let storeDirectoryURL: URL
    let cloudKitEnabled: Bool
    let defaults: UserDefaults

    init(
        isEphemeral: Bool = false,
        storeDirectoryURL: URL? = nil,
        cloudKitEnabled: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        self.isEphemeral = isEphemeral
        self.cloudKitEnabled = cloudKitEnabled
        self.defaults = defaults
        self.storeDirectoryURL =
            storeDirectoryURL
            ?? (isEphemeral
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

        lockedContainer = Self.makeContainer()
        lockedContainer.persistentStoreDescriptions = Self.makeStoreDescriptions(
            directory: self.storeDirectoryURL,
            isEphemeral: isEphemeral,
            cloudKitEnabled: cloudKitEnabled
        )
    }

    static let cloudKitLocalEnvironmentKey = "onecart.cloudkit-local-environment"

    func load() async throws {
        try await load(duringAccountDeletion: false)
    }

    /// Account deletion reattaches stores with its flag still set, so repository calls stay
    /// rejected until the rebuilt container has its stores instead of running on an empty one.
    func load(duringAccountDeletion: Bool) async throws {
        if !duringAccountDeletion {
            try checkAccountDeletionAllowsStoreAccess()
        }
        if isLoaded {
            return
        }

        do {
            try await loadPersistentStoresOnce(duringAccountDeletion: duringAccountDeletion)
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
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    func performBackgroundTask<T: Sendable>(
        author: String = "OneCartRepository",
        _ block: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try checkAccountDeletionAllowsStoreAccess()
        return try await withCheckedThrowingContinuation { continuation in
            let context = newBackgroundContext(author: author)
            context.perform {
                do {
                    try self.checkAccountDeletionAllowsStoreAccess()
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
        guard !isEphemeral else { return }
        // The store reference is only handed back to the container; it is never mutated here.
        nonisolated(unsafe) let sharedStore = try store(for: .shared)
        try await CloudKitDeadline.run(timeoutNanoseconds: 22_000_000_000) {
            try await self.acceptShareInvitationsWithoutTimeout(metadata, into: sharedStore)
        }
    }

    private func acceptShareInvitationsWithoutTimeout(
        _ metadata: [CKShare.Metadata],
        into sharedStore: NSPersistentStore
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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

    private func loadPersistentStoresOnce(duringAccountDeletion: Bool) async throws {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            loadLock.lock()
            if accountDeletionInProgress, !duringAccountDeletion {
                loadLock.unlock()
                continuation.resume(returning: .failure(AccountDeletionStoreError.deletionInProgress))
                return
            }
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

            // The pre-load preparation may destroy store files or rebuild the container, so it
            // runs only in the single flight's leader; no lock is held while it works.
            let recoveringDeletion: Bool
            do {
                recoveringDeletion = try self.prepareAccountDeletionRecoveryBeforeLoad()
                if !recoveringDeletion {
                    try self.reconcileCloudKitEnvironmentBeforeLoad()
                }
            } catch {
                finishLoading(firstError: error, stampsEnvironment: false)
                return
            }

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
                        // swiftlint:disable:next line_length
                        "Failed loading \(description.url?.lastPathComponent ?? "store", privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    logger.info(
                        "Loaded \(description.url?.lastPathComponent ?? "store", privacy: .public)"
                    )
                }

                guard isFinished else { return }
                finishLoading(firstError: firstError, stampsEnvironment: !recoveringDeletion)
            }
        }

        try result.get()
    }

    private func finishLoading(firstError: Error?, stampsEnvironment: Bool) {
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
                if stampsEnvironment {
                    stampCloudKitEnvironmentAfterSuccessfulLoad()
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
        }
        if case .failure = result {
            detachPartiallyLoadedStores()
        }

        loading = false
        let waiters = loadWaiters
        loadWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }
}

// MARK: - Load recovery and store identity

extension PersistenceController {
    /// A store that loaded next to one that failed stays attached to the coordinator, and the next
    /// `loadPersistentStores` then fails it with Cocoa 134081 ("can't add the same store twice").
    /// Detaching keeps a retry in the same process possible. `remove(_:)` only closes the store;
    /// the files stay on disk (invariant F1).
    private func detachPartiallyLoadedStores() {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            do {
                try coordinator.remove(store)
            } catch {
                logger.error(
                    // swiftlint:disable:next line_length
                    "Unable to detach \(store.url?.lastPathComponent ?? "store", privacy: .public) after a failed load: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        privateStore = nil
        sharedStore = nil
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
        context.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        context.shouldDeleteInaccessibleFaults = true
    }
}
