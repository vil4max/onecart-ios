import CloudKit
import CoreData
@testable import OneCart
import XCTest

/// Joining through an invite (REQ-SHARE-090): the session drains the inbox the delegates fill,
/// puts back invitations whose accept failed, and treats a benign failure for a cart it already
/// holds as joined.
extension GuestMemberSessionTests {
    private var familyRoot: CKRecord.ID {
        CKRecord.ID(recordName: "family-root", zoneID: FakeCloudKitShareStore.zoneID)
    }

    private func invitation(_ shareName: String, rootRecordID: CKRecord.ID? = nil) -> PendingShareInvitation {
        PendingShareInvitation(participantStatus: .pending, shareRecordName: shareName, rootRecordID: rootRecordID)
    }

    func test_REQ_SHARE_090_inboxHandsOutInvitationsOnceInArrivalOrder() {
        let inbox = LivePendingShareInbox()
        inbox.enqueue(invitation("first"))
        inbox.enqueue(invitation("second"))

        XCTAssertEqual(inbox.takeAll().map(\.shareRecordName), ["first", "second"])
        XCTAssertTrue(inbox.takeAll().isEmpty)

        inbox.enqueue(invitation("third"))
        inbox.requeue([invitation("first")])
        XCTAssertEqual(inbox.takeAll().map(\.shareRecordName), ["third", "first"])
    }

    func test_REQ_SHARE_090_failedAcceptIsRequeuedAndReported() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let inbox = LivePendingShareInbox()
        let accepter = FakeShareInvitationAccepter(failingWith: CKError(.networkFailure))
        let session = try makeTestSession(persistence: persistence, shareInbox: inbox, shareAccepter: accepter)
        inbox.enqueue(invitation("family-share"))

        await session.acceptPendingCloudKitShares()

        XCTAssertEqual(accepter.acceptedShareNames, [["family-share"]])
        XCTAssertEqual(session.syncState, .failed)
        XCTAssertEqual(session.userAlert?.kind, .error)
        XCTAssertEqual(inbox.takeAll().map(\.shareRecordName), ["family-share"], "The next attempt retries it")
    }

    func test_REQ_SHARE_090_benignFailureForAnAlreadyJoinedCartCountsAsJoined() async throws {
        let inbox = LivePendingShareInbox()
        let accepter = FakeShareInvitationAccepter(failingWith: CKError(.alreadyShared))
        let fixture = try await makeGuestFixture(
            sharedName: "Family",
            sharedProduct: "Milk",
            shareInbox: inbox,
            shareAccepter: accepter
        )
        let session = fixture.session
        // The fake container names every object's record `family-root`, so the shared cart the
        // guest already holds matches the invitation's root record.
        inbox.enqueue(invitation("family-share", rootRecordID: familyRoot))

        await session.acceptPendingCloudKitShares()

        XCTAssertEqual(accepter.acceptedShareNames, [["family-share"]])
        XCTAssertEqual(session.syncState, .synchronized)
        XCTAssertNil(session.userAlert)
        XCTAssertTrue(inbox.takeAll().isEmpty, "A joined cart is not retried")
        XCTAssertEqual(session.activeFamilySpace?.id, fixture.sharedID)
    }

    func test_REQ_SHARE_090_benignFailureWithoutAMatchingCartIsRequeued() async throws {
        let inbox = LivePendingShareInbox()
        let accepter = FakeShareInvitationAccepter(failingWith: CKError(.alreadyShared))
        let fixture = try await makeGuestFixture(
            sharedName: "Family",
            sharedProduct: "Milk",
            shareInbox: inbox,
            shareAccepter: accepter
        )
        let otherRoot = CKRecord.ID(recordName: "other-root", zoneID: FakeCloudKitShareStore.zoneID)
        inbox.enqueue(invitation("other-share", rootRecordID: otherRoot))

        await fixture.session.acceptPendingCloudKitShares()

        XCTAssertEqual(fixture.session.syncState, .failed)
        XCTAssertEqual(inbox.takeAll().map(\.shareRecordName), ["other-share"])
    }

    func test_REQ_SHARE_090_acceptedInvitationsSkipTheContainer() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let inbox = LivePendingShareInbox()
        let accepter = FakeShareInvitationAccepter()
        let session = try makeTestSession(persistence: persistence, shareInbox: inbox, shareAccepter: accepter)
        inbox.enqueue(
            PendingShareInvitation(participantStatus: .accepted, shareRecordName: "joined", rootRecordID: nil)
        )

        await session.acceptPendingCloudKitShares()

        XCTAssertTrue(accepter.acceptedShareNames.isEmpty)
        XCTAssertEqual(session.syncState, .synchronized)
        XCTAssertTrue(inbox.takeAll().isEmpty)
    }
}
