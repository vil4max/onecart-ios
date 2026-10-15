import CloudKit
import CoreData
@testable import OneCart
import Synchronization
import Testing

/// The guest's leave (REQ-SHARE-050) on `CloudKitBackendService` with a fake container: the zone
/// purge runs under a deadline on the test clock, and a purge that outlives it reports in once.
@Suite("Leave purge", .removesStores)
@MainActor
struct LeaveFamilyPurgeTests {
    @Test("REQ-SHARE-050: a purge that finishes in time lets the leave return normally")
    func purgeInTimeReturnsNormally() async throws {
        let fixture = try await CartFixture.make()
        let store = FakeCloudKitShareStore()
        let backend = CloudKitBackendService(persistence: fixture.persistence, shareStore: store)
        let latePurges = Mutex(0)

        let discardLeftovers = try await backend.leaveFamily(objectID: try fixture.family.objectID) {
            latePurges.withLock { $0 += 1 }
        }

        #expect(discardLeftovers)
        #expect(store.purgeCalls == [.init(zoneID: FakeCloudKitShareStore.zoneID, scope: .shared)])
        #expect(latePurges.withLock { $0 } == 0)
    }

    @Test("REQ-SHARE-050: a purge past the timeout throws leaveTimedOut, and its late completion is reported once")
    func purgePastTimeoutReportsLateCompletionOnce() async throws {
        let fixture = try await CartFixture.make()
        let store = FakeCloudKitShareStore(purgeOutcome: .hold)
        let clock = TestClock()
        let backend = CloudKitBackendService(
            persistence: fixture.persistence,
            shareStore: store,
            clock: clock.appClock
        )
        let objectID = try fixture.family.objectID
        let latePurges = Mutex(0)

        let leave = Task {
            try await backend.leaveFamily(objectID: objectID) {
                latePurges.withLock { $0 += 1 }
            }
        }
        #expect(await clock.waitForSleepers(), "the purge deadline waits on the clock")
        clock.advance(by: CloudKitBackendService.leavePurgeTimeout)
        await expectCloudKitError(.leaveTimedOut) {
            _ = try await leave.value
        }
        #expect(latePurges.withLock { $0 } == 0)

        for _ in 0..<10_000 where !store.isHoldingPurge {
            await Task.yield()
        }
        store.finishHeldPurge()
        for _ in 0..<10_000 where latePurges.withLock({ $0 }) == 0 {
            await Task.yield()
        }
        for _ in 0..<100 {
            await Task.yield()
        }

        #expect(latePurges.withLock { $0 } == 1)
        #expect(store.purgeCalls.count == 1)
    }

    @Test("REQ-SHARE-050: a zone that is already gone counts as left; any other purge error is rethrown")
    func zoneGoneIsSuccessOtherErrorsRethrow() async throws {
        let fixture = try await CartFixture.make()
        let objectID = try fixture.family.objectID
        let zoneGone = CloudKitBackendService(
            persistence: fixture.persistence,
            shareStore: FakeCloudKitShareStore(purgeOutcome: .fail(CKError(.zoneNotFound)))
        )
        let offline = CloudKitBackendService(
            persistence: fixture.persistence,
            shareStore: FakeCloudKitShareStore(purgeOutcome: .fail(CKError(.networkFailure)))
        )

        #expect(try await zoneGone.leaveFamily(objectID: objectID))
        do {
            _ = try await offline.leaveFamily(objectID: objectID)
            Issue.record("a network failure must not count as left")
        } catch let error as CKError {
            #expect(error.code == .networkFailure)
        }
    }
}
