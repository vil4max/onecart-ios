import CoreData
import Foundation

/// Deletes the signed-in user's private CloudKit account data.
protocol AccountCloudDataDeleting: AnyObject {
    func deletePrivateAccountCloudData() async throws
}

extension CloudKitBackendService: AccountCloudDataDeleting {}

/// Unloads / reloads local Core Data stores around CloudKit account deletion.
protocol AccountLocalStorePreparing: AnyObject {
    func detachLocalStoresForCloudAccountDeletion() async throws
    func attachEmptyLocalStoresAfterCloudAccountDeletion() async throws
    func restoreLocalStoresAfterFailedCloudAccountDeletion() async throws
}

extension PersistenceController: AccountLocalStorePreparing {
    func detachLocalStoresForCloudAccountDeletion() async throws {
        if try readAccountDeletionPhase() == .cloudDeleted {
            try beginAccountStoreDeletion()
            return
        }
        try beginAccountStoreDeletion()
        do {
            try writeAccountDeletionPhase(.pendingCloud)
            let context = container.viewContext
            try await context.perform {
                if context.hasChanges {
                    try context.save()
                }
                context.reset()
            }
            try await removeAccountStoresFromCoordinator()
        } catch {
            finishAccountStoreDeletion()
            try? await restoreLocalStoresAfterFailedCloudAccountDeletion()
            throw error
        }
    }

    func attachEmptyLocalStoresAfterCloudAccountDeletion() async throws {
        defer { finishAccountStoreDeletion() }
        // Keep the marker until every old store is gone, including across a failed cleanup or relaunch.
        try writeAccountDeletionPhase(.cloudDeleted)
        try destroyDetachedAccountStores()
        finishAccountStoreDeletion()
        rebuildContainerAfterAccountDeletion(cloudKitEnabled: cloudKitEnabled)
        try await load()
    }

    func restoreLocalStoresAfterFailedCloudAccountDeletion() async throws {
        guard try readAccountDeletionPhase() != .cloudDeleted else {
            throw AccountDeletionStoreError.cleanupRequired
        }
        try await removeAccountStoresFromCoordinator()
        finishAccountStoreDeletion()
        rebuildContainerAfterAccountDeletion(cloudKitEnabled: cloudKitEnabled && !accountDeletionRecoveryRequired)
        try await load()
    }

    enum AccountDeletionPhase: String, Codable {
        case pendingCloud
        case cloudDeleted
    }

    enum AccountDeletionStoreError: LocalizedError {
        case deletionInProgress
        case cleanupRequired

        var errorDescription: String? {
            String(localized: "account.delete_failed")
        }
    }

    var accountDeletionRecoveryRequired: Bool {
        FileManager.default.fileExists(atPath: accountDeletionMarkerURL.path)
    }

    var accountDeletionMarkerURL: URL {
        storeDirectoryURL.appendingPathComponent("account-deletion-state.json")
    }

    func writeAccountDeletionPhase(_ phase: AccountDeletionPhase) throws {
        try JSONEncoder().encode(phase).write(to: accountDeletionMarkerURL, options: .atomic)
    }

    func readAccountDeletionPhase() throws -> AccountDeletionPhase? {
        guard FileManager.default.fileExists(atPath: accountDeletionMarkerURL.path) else { return nil }
        return try JSONDecoder().decode(
            AccountDeletionPhase.self,
            from: Data(contentsOf: accountDeletionMarkerURL)
        )
    }

    func prepareAccountDeletionRecoveryBeforeLoad() throws -> Bool {
        switch try readAccountDeletionPhase() {
        case .pendingCloud:
            // A failed request may still have deleted zones. Preserve local data without re-exporting it.
            container.persistentStoreDescriptions = Self.makeStoreDescriptions(
                directory: storeDirectoryURL,
                inMemory: inMemory,
                cloudKitEnabled: false
            )
            return true
        case .cloudDeleted:
            try destroyDetachedAccountStores()
            rebuildContainerAfterAccountDeletion(cloudKitEnabled: cloudKitEnabled)
            return false
        case nil:
            return false
        }
    }

    func destroyDetachedAccountStores(destroyStore: ((URL) throws -> Void)? = nil) throws {
        guard container.persistentStoreCoordinator.persistentStores.isEmpty,
              try readAccountDeletionPhase() == .cloudDeleted
        else { throw AccountDeletionStoreError.cleanupRequired }
        let coordinator = container.persistentStoreCoordinator
        for fileName in ["OneCart-private.sqlite", "OneCart-shared.sqlite"] {
            let url = storeDirectoryURL.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let destroyStore {
                try destroyStore(url)
            } else {
                try coordinator.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
            }
        }
        try FileManager.default.removeItem(at: accountDeletionMarkerURL)
    }

    func checkAccountDeletionAllowsStoreAccess() throws {
        loadLock.lock()
        defer { loadLock.unlock() }
        guard !accountDeletionInProgress else { throw AccountDeletionStoreError.deletionInProgress }
    }

    private func beginAccountStoreDeletion() throws {
        loadLock.lock()
        defer { loadLock.unlock() }
        guard !accountDeletionInProgress, !loading else {
            throw AccountDeletionStoreError.deletionInProgress
        }
        accountDeletionInProgress = true
    }

    private func finishAccountStoreDeletion() {
        loadLock.lock()
        accountDeletionInProgress = false
        loadLock.unlock()
    }

    private func removeAccountStoresFromCoordinator() async throws {
        let coordinator = container.persistentStoreCoordinator
        try await coordinator.perform {
            for store in coordinator.persistentStores {
                try coordinator.remove(store)
            }
        }
        markAccountStoresDetached()
    }

    private func markAccountStoresDetached() {
        loadLock.lock()
        loaded = false
        privateStore = nil
        sharedStore = nil
        loadLock.unlock()
    }

    private func rebuildContainerAfterAccountDeletion(cloudKitEnabled: Bool) {
        container = Self.makeContainer()
        container.persistentStoreDescriptions = Self.makeStoreDescriptions(
            directory: storeDirectoryURL,
            inMemory: inMemory,
            cloudKitEnabled: cloudKitEnabled
        )
    }
}
