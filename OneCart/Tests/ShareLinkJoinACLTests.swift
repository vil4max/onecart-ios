import CloudKit
@testable import OneCart
import XCTest

@MainActor
final class ShareLinkJoinACLTests: XCTestCase {
    func test_REQ_SHARE_080_backgroundInvitePreparation_keepsRevokedShareClosed() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .none
        XCTAssertThrowsError(try FamilyInviteLinkBuilder.linkForOpenShare(share, displayName: "Family")) { error in
            guard case OneCartCloudKitError.inviteDoorClosed = error else {
                return XCTFail("Expected the revoked invite to remain unavailable")
            }
        }
        XCTAssertEqual(share.publicPermission, .none)
    }

    func test_REQ_SHARE_060_applyReadWriteACLPreservesRevokedPublicPermission() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .none
        XCTAssertFalse(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertEqual(share.publicPermission, .none)
    }

    func test_REQ_SHARE_070_applyReadWriteACLReopensDoorWhenRequested() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .none
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share, reopenInviteDoor: true))
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func test_REQ_SHARE_060_revokeIsDoorCloseNotGuestBan() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readWrite
        share.publicPermission = .none
        XCTAssertEqual(share.publicPermission, .none)
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share, reopenInviteDoor: true))
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func testApplyReadWriteACLUpgradesUnknownOrReadOnlyPublicPermission() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readOnly
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func testApplyReadWriteACLIsIdempotent() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readWrite
        XCTAssertFalse(OneCartShareLinkJoin.applyReadWriteACL(to: share))
    }

    /// The participant upgrade loop is not reachable from a unit test: `CKShare.Participant`
    /// has no public initializer, and `oneTimeURLParticipant()` raises without the
    /// `com.apple.developer.icloud-extended-share-access` entitlement. This covers only the
    /// owner-only share, which must report no change and leave the owner alone.
    func testApplyReadWriteACLLeavesOwnerOnlyOpenShareUnchanged() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        share.publicPermission = .readWrite
        XCTAssertEqual(share.participants.map(\.role), [.owner])
        let ownerPermission = share.owner.permission

        XCTAssertFalse(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertEqual(share.publicPermission, .readWrite)
        XCTAssertEqual(share.participants.map(\.role), [.owner])
        XCTAssertEqual(share.owner.permission, ownerPermission)
    }
}
