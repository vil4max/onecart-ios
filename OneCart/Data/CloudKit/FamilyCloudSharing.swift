import CoreData
import Foundation

/// Everything the session, the bootstrapper and the share orchestrator ask of iCloud: the account,
/// cart access, members and the `CKShare` lifecycle, plus the user identity and account-data
/// deletion it inherits. `CloudKitBackendService` is the only production conformer; tests and the
/// DEBUG demo inject `InMemoryFamilySharing`, so no production path forks on the store kind.
///
/// Async share mutations take the object ID: a view-context `FamilySpace` must not leave the main
/// actor. The synchronous members read a view-context `FamilySpace`, so they are main-actor
/// requirements.
protocol FamilyCloudSharing: CloudUserIdentifying, AccountCloudDataDeleting {
    func restoredAccount(appleUserID: String, displayName: String?) async throws -> OneCartAccount
    @MainActor func access(for family: FamilySpace) -> FamilyAccess
    @MainActor func familyMembers(
        for family: FamilySpace,
        account: OneCartAccount,
        currentUserRecordName: String?
    ) throws -> [FamilyMember]
    func createFamilyInviteLink(objectID: NSManagedObjectID, displayName: String) async throws -> FamilyInviteLink
    func revokeInviteLink(objectID: NSManagedObjectID) async throws
    /// Returns whether the share changed and was saved.
    @discardableResult
    func ensureReadWriteACL(objectID: NSManagedObjectID) async throws -> Bool
    func removeMember(_ member: FamilyMember, fromFamily objectID: NSManagedObjectID) async throws
    /// Returns whether the caller should discard the local leftovers of the shared cart. When it
    /// throws `leaveTimedOut`, the purge may still finish: `onLatePurgeCompletion` then runs once,
    /// so the caller's leave recovery can react (REQ-SHARE-050).
    @discardableResult
    func leaveFamily(
        objectID: NSManagedObjectID,
        onLatePurgeCompletion: @escaping @Sendable () -> Void
    ) async throws -> Bool
}

extension FamilyCloudSharing {
    /// A leave whose caller has no recovery to run after a timeout.
    @discardableResult
    func leaveFamily(objectID: NSManagedObjectID) async throws -> Bool {
        try await leaveFamily(objectID: objectID, onLatePurgeCompletion: {})
    }
}

extension CloudKitBackendService: FamilyCloudSharing {}
