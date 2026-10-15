@testable import OneCart
import XCTest

@MainActor
final class MemberJoinDiffTests: XCTestCase {
    func test_REQ_WIDGET_030_firstSnapshotSeedsWithoutNotify() {
        let member = FamilyMember(
            id: UUID(),
            displayName: "Sam",
            access: .member,
            joinedAt: Date(),
            isCurrentUser: false,
            avatarURL: nil,
            bannerURL: nil
        )
        let diff = MemberJoinDiff.evaluate(
            previousIDs: [],
            storedIDs: [],
            current: [member]
        )
        XCTAssertFalse(diff.shouldNotify)
        XCTAssertTrue(diff.newcomerIDs.isEmpty)
        XCTAssertEqual(diff.nextStoredIDs, [member.id])
    }

    func test_REQ_WIDGET_030_newMemberAfterBaselineNotifies() {
        let existingID = UUID()
        let newID = UUID()
        let existing = FamilyMember(
            id: existingID,
            displayName: "Alex",
            access: .owner,
            joinedAt: Date(),
            isCurrentUser: true,
            avatarURL: nil,
            bannerURL: nil
        )
        let joined = FamilyMember(
            id: newID,
            displayName: "Sam",
            access: .member,
            joinedAt: Date(),
            isCurrentUser: false,
            avatarURL: nil,
            bannerURL: nil
        )
        let diff = MemberJoinDiff.evaluate(
            previousIDs: [existingID],
            storedIDs: [existingID],
            current: [existing, joined]
        )
        XCTAssertTrue(diff.shouldNotify)
        XCTAssertEqual(diff.newcomerIDs, [newID])
        XCTAssertEqual(diff.nextStoredIDs, [existingID, newID])
    }
}
