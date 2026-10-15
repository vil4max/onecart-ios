import CoreData
import Foundation
@testable import OneCart
import Synchronization

/// `InMemoryFamilySharing` that also records what the share orchestrator asked of it. With
/// `holdsInviteLink`, invite creation waits until it is cancelled, so a test can cancel the caller.
final class RecordingFamilySharing: FamilyCloudSharing {
    struct Record {
        var aclHealCount = 0
        var inviteLinkStarts = 0
        var inviteLinkCancelled = false
        /// Whether the view context still had unsaved changes when invite creation began.
        var viewContextDirtyAtInvite: Bool?
    }

    private let base: InMemoryFamilySharing
    private let persistence: PersistenceController
    private let holdsInviteLink: Bool
    private let state = Mutex(Record())

    init(persistence: PersistenceController, holdsInviteLink: Bool = false) {
        base = InMemoryFamilySharing(persistence: persistence)
        self.persistence = persistence
        self.holdsInviteLink = holdsInviteLink
    }

    var record: Record {
        state.withLock { $0 }
    }

    var identityGeneration: UInt64 {
        base.identityGeneration
    }

    func currentUserRecordName() async -> String? {
        await base.currentUserRecordName()
    }

    func resetCachedUserRecordName() {
        base.resetCachedUserRecordName()
    }

    func deletePrivateAccountCloudData() async throws {
        try await base.deletePrivateAccountCloudData()
    }

    func restoredAccount(appleUserID: String, displayName: String?) async throws -> OneCartAccount {
        try await base.restoredAccount(appleUserID: appleUserID, displayName: displayName)
    }

    func access(for family: FamilySpace) -> FamilyAccess {
        base.access(for: family)
    }

    func familyMembers(
        for family: FamilySpace,
        account: OneCartAccount,
        currentUserRecordName: String?
    ) throws -> [FamilyMember] {
        try base.familyMembers(for: family, account: account, currentUserRecordName: currentUserRecordName)
    }

    func createFamilyInviteLink(objectID: NSManagedObjectID, displayName: String) async throws -> FamilyInviteLink {
        let persistence = persistence
        let dirty = await MainActor.run { persistence.container.viewContext.hasChanges }
        state.withLock {
            $0.inviteLinkStarts += 1
            $0.viewContextDirtyAtInvite = dirty
        }
        if holdsInviteLink {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                state.withLock { $0.inviteLinkCancelled = true }
                throw error
            }
        }
        return try await base.createFamilyInviteLink(objectID: objectID, displayName: displayName)
    }

    func revokeInviteLink(objectID: NSManagedObjectID) async throws {
        try await base.revokeInviteLink(objectID: objectID)
    }

    func ensureReadWriteACL(objectID: NSManagedObjectID) async throws -> Bool {
        state.withLock { $0.aclHealCount += 1 }
        return try await base.ensureReadWriteACL(objectID: objectID)
    }

    func removeMember(_ member: FamilyMember, fromFamily objectID: NSManagedObjectID) async throws {
        try await base.removeMember(member, fromFamily: objectID)
    }

    func leaveFamily(objectID: NSManagedObjectID) async throws -> Bool {
        try await base.leaveFamily(objectID: objectID)
    }
}
