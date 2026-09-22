import CloudKit
import CoreData
@testable import OneCart
import Testing

/// The builder's CloudKit round trips (share creation, persistence, mirroring) need a live
/// container; these tests cover the decisions it makes before and around them.
@Suite("FamilyInviteLinkBuilder")
@MainActor
struct FamilyInviteLinkBuilderTests {
    private func makeShare(publicPermission: CKShare.ParticipantPermission) -> CKShare {
        let zoneID = CKRecordZone.ID(zoneName: "InviteZone", ownerName: CKCurrentUserDefaultName)
        let root = CKRecord(
            recordType: "FamilySpace",
            recordID: CKRecord.ID(recordName: "family-root", zoneID: zoneID)
        )
        let share = CKShare(rootRecord: root)
        share.publicPermission = publicPermission
        return share
    }

    @Test("REQ-SHARE-060: a revoked share yields no link and stays closed")
    func revokedShareYieldsNoLink() async {
        let share = makeShare(publicPermission: .none)

        await expectCloudKitError(.inviteDoorClosed) {
            _ = try FamilyInviteLinkBuilder.linkForOpenShare(share, displayName: "Family")
        }
        #expect(share.publicPermission == .none)
    }

    @Test("REQ-SHARE-010: only a read-write door counts as open; read-only is still closed")
    func readOnlyDoorIsClosed() async {
        let share = makeShare(publicPermission: .readOnly)

        await expectCloudKitError(.inviteDoorClosed) {
            _ = try FamilyInviteLinkBuilder.linkForOpenShare(share, displayName: "Family")
        }
        #expect(share.publicPermission == .readOnly)
    }

    @Test("REQ-SHARE-080: an open share without a server URL is reported as still syncing")
    func openShareWithoutURLIsStillSyncing() async {
        let share = makeShare(publicPermission: .readWrite)
        #expect(share.url == nil)

        await expectCloudKitError(.stillSyncing) {
            _ = try FamilyInviteLinkBuilder.linkForOpenShare(share, displayName: "Family")
        }
        #expect(share.publicPermission == .readWrite)
    }

    @Test("Link identity is a stable UUID of the share record name")
    func linkIdentityIsStableForRecordName() {
        let first = FamilyInviteLinkBuilder.stableUUID(for: "Share-ABC")
        #expect(first == FamilyInviteLinkBuilder.stableUUID(for: "Share-ABC"))
        #expect(first == OneCartStableID.uuid(for: "Share-ABC"))
        #expect(first != FamilyInviteLinkBuilder.stableUUID(for: "Share-ABD"))
        #expect(first != FamilyInviteLinkBuilder.stableUUID(for: "share-abc"))
    }

    @Test("REQ-SHARE-080: background preparation never creates a share; a cart without one is still syncing")
    func existingLinkForUnsharedCartIsStillSyncingAndReadOnly() async throws {
        let fixture = try await CartFixture.make()
        let family = try fixture.family
        let updatedAtBefore = family.updatedAt

        await expectCloudKitError(.stillSyncing) {
            _ = try await FamilyInviteLinkBuilder.existingInviteLink(
                persistence: fixture.persistence,
                objectID: family.objectID,
                displayName: family.displayName
            )
        }

        await fixture.settle()
        #expect(try fixture.family.updatedAt == updatedAtBefore)
    }

    @Test("A cart that no longer exists surfaces the Core Data failure, not a CloudKit state")
    func existingLinkForDeletedCartSurfacesStoreFailure() async throws {
        let fixture = try await CartFixture.make()
        let objectID = try fixture.family.objectID
        try await fixture.persistence.performBackgroundTask { context in
            try context.delete(context.existingObject(with: objectID))
        }
        await fixture.settle()

        do {
            _ = try await FamilyInviteLinkBuilder.existingInviteLink(
                persistence: fixture.persistence,
                objectID: objectID,
                displayName: "Family"
            )
            Issue.record("expected a Core Data failure for a deleted cart")
        } catch is OneCartCloudKitError {
            Issue.record("a missing cart must not be reported as a CloudKit state")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
        }
    }

    @Test("REQ-SHARE-030: a cancelled invite request stops before touching the cart")
    func cancelledInviteRequestLeavesCartUntouched() async throws {
        let fixture = try await CartFixture.make()
        let family = try fixture.family
        let objectID = family.objectID
        let updatedAtBefore = family.updatedAt
        let persistence = fixture.persistence

        // The task inherits the main actor, so it cannot start before `cancel()` runs.
        let request = Task {
            try await FamilyInviteLinkBuilder.makeInviteLink(
                persistence: persistence,
                objectID: objectID,
                displayName: "Family"
            )
        }
        request.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
        await fixture.settle()
        #expect(try fixture.family.updatedAt == updatedAtBefore)
    }
}
