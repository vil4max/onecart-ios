import CoreData
import Foundation

/// Deletes the signed-in user's private CloudKit account data.
protocol AccountCloudDataDeleting: AnyObject, Sendable {
    func deletePrivateAccountCloudData() async throws
}

extension CloudKitBackendService: AccountCloudDataDeleting {}

/// Records the boundary between harmless preparation and the destructive zone deletion request.
protocol AccountDeletionRequestMarking: AnyObject, Sendable {
    func markDestructiveCloudDeletionRequestStarting() throws
}

/// Unloads / reloads local Core Data stores around CloudKit account deletion.
protocol AccountLocalStorePreparing: AnyObject, Sendable {
    func detachLocalStoresForCloudAccountDeletion() async throws
    func attachEmptyLocalStoresAfterCloudAccountDeletion() async throws
    func restoreLocalStoresAfterFailedCloudAccountDeletion() async throws
}
