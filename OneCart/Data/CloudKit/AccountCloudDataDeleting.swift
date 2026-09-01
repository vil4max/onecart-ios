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
}

extension PersistenceController: AccountLocalStorePreparing {
    func detachLocalStoresForCloudAccountDeletion() async throws {
        guard !inMemory else { return }
        try hardResetPersistentStores()
    }

    func attachEmptyLocalStoresAfterCloudAccountDeletion() async throws {
        guard !inMemory else { return }
        try await load()
    }
}
