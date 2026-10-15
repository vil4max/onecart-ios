import CloudKit
import CoreData
@testable import OneCart
import XCTest

/// A guest's leave whose zone purge outlives its deadline (REQ-SHARE-050). The session runs on
/// the real `CloudKitBackendService` over a fake container; the purge deadline and the recovery
/// passes each have their own test clock, so moving one never wakes the other.
extension GuestMemberSessionTests {
    func test_REQ_SHARE_050_leaveTimeoutShowsAlertAndLatePurgeEndsRecovery() async throws {
        let leave = try await makeTimedOutLeave()
        let session = leave.fixture.session

        XCTAssertEqual(
            session.userAlert,
            .error(CloudKitUserFacingError.message(for: OneCartCloudKitError.leaveTimedOut))
        )
        XCTAssertTrue(session.lastActiveFamilyWasShared)
        XCTAssertEqual(session.activeFamilySpace?.id, leave.fixture.sharedID)
        let recovery = try XCTUnwrap(session.leaveRecoveryTask)

        // The purge clears the shared cart locally, then its late callback arrives.
        try await session.repository.discardLocalSharedFamilySpace(id: leave.fixture.sharedID)
        leave.store.finishHeldPurge()
        await recovery.value

        XCTAssertEqual(session.activeFamilySpace?.id, leave.fixture.privateID)
        XCTAssertEqual(session.access, .owner)
        XCTAssertEqual(leave.sessionClock.pendingSleepers, 0, "The late purge ended recovery before any timed pass")
    }

    func test_REQ_SHARE_050_latePurgeThatLeavesTheCartKeepsTheTimedPasses() async throws {
        let leave = try await makeTimedOutLeave()
        let session = leave.fixture.session
        @MainActor final class Done {
            var value = false
        }
        let done = Done()
        let recovery = try XCTUnwrap(session.leaveRecoveryTask)
        let watcher = Task {
            await recovery.value
            done.value = true
        }

        // The late purge reports in while the shared cart is still on disk: its one pass fails.
        leave.store.finishHeldPurge()
        for _ in 0..<1_000 {
            await Task.yield()
        }
        XCTAssertFalse(done.value, "A late purge that did not clear the cart does not end recovery")
        let waiting = await leave.sessionClock.waitForSleepers()
        XCTAssertTrue(waiting, "The timed pass still waits on the clock")

        try await session.repository.discardLocalSharedFamilySpace(id: leave.fixture.sharedID)
        leave.sessionClock.advance(by: AppSession.leaveRecoveryInterval)
        await watcher.value

        XCTAssertEqual(session.activeFamilySpace?.id, leave.fixture.privateID)
        XCTAssertEqual(leave.sessionClock.pendingSleepers, 0)
    }

    private struct TimedOutLeave {
        var fixture: GuestFixture
        var store: FakeCloudKitShareStore
        var sessionClock: TestClock
    }

    /// Leaves the shared cart with a purge that never answers, and lets the purge deadline pass.
    private func makeTimedOutLeave() async throws -> TimedOutLeave {
        let store = FakeCloudKitShareStore(purgeOutcome: .hold)
        let purgeClock = TestClock()
        let sessionClock = TestClock()
        let fixture = try await makeGuestFixture(
            sharedName: "Family",
            sharedProduct: "Milk",
            clock: sessionClock.appClock
        ) { persistence in
            CloudKitBackendService(persistence: persistence, shareStore: store, clock: purgeClock.appClock)
        }
        XCTAssertEqual(fixture.session.access, .member)

        let session = fixture.session
        let leave = Task { await session.leaveCurrentFamily() }
        let purgeWaiting = await purgeClock.waitForSleepers()
        XCTAssertTrue(purgeWaiting, "The purge deadline waits on its clock")
        purgeClock.advance(by: CloudKitBackendService.leavePurgeTimeout)
        await leave.value
        for _ in 0..<10_000 where !store.isHoldingPurge {
            await Task.yield()
        }
        XCTAssertTrue(store.isHoldingPurge)
        return TimedOutLeave(fixture: fixture, store: store, sessionClock: sessionClock)
    }
}
