import CoreData
@testable import OneCart
import XCTest

/// `CloudSyncCoordinator` over a bare `CartSyncService`: the scheduled reload and how a sync
/// outcome reaches the sync state and alerts.
extension FragileSyncOutcomeTests {
    func testCloudReloadScheduledRightAfterCancelStillRuns() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let refresher = ScriptedCartRefresher()
        cartSync.refresher = refresher
        let clock = TestClock()
        let context = ReloadCountingContext()
        let coordinator = CloudSyncCoordinator(
            persistence: persistence, cartSync: cartSync, clock: clock.appClock, context: context)

        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)
        coordinator.cancel()
        // The cancelled task has not run its cleanup yet; the new request must not be dropped.
        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)

        let reloaded = await clock.advanceWhenSleeping(by: .milliseconds(20)) { context.reloadCount >= 1 }
        XCTAssertTrue(reloaded)
        XCTAssertEqual(context.reloadCount, 1)
    }

    func testShorterCloudReloadDelayReschedulesPendingReload() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let refresher = ScriptedCartRefresher()
        cartSync.refresher = refresher
        let clock = TestClock()
        let context = ReloadCountingContext()
        let coordinator = CloudSyncCoordinator(
            persistence: persistence, cartSync: cartSync, clock: clock.appClock, context: context)
        defer { coordinator.cancel() }

        coordinator.scheduleCloudReload(delayNanoseconds: 30_000_000_000)
        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)

        // Only the shorter delay passes; the 30 s request must not be what runs the reload.
        let reloaded = await clock.advanceWhenSleeping(by: .milliseconds(20)) { context.reloadCount >= 1 }
        XCTAssertTrue(reloaded)
        XCTAssertEqual(context.reloadCount, 1)
    }

    func test_REQ_SHELL_050_foregroundSyncFailureAlertsOnlyAfterHealthyState() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let refresher = ScriptedCartRefresher {
            throw NSError(domain: "Sync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foreground failed"])
        }
        cartSync.refresher = refresher
        let context = ReloadCountingContext()
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync, context: context)

        context.syncState = .synchronized
        context.applyResult(await coordinator.syncCart(reason: .foreground))
        XCTAssertEqual(context.syncAlerts, ["Foreground failed"])
        XCTAssertEqual(context.syncState, .failed)

        context.applyResult(await coordinator.syncCart(reason: .foreground))
        XCTAssertEqual(context.syncAlerts.count, 1, "A failure after a failure stays silent")
    }

    func test_REQ_SYNC_010_cancelledRefreshIsReportedAsCancelled() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let refresher = ScriptedCartRefresher { throw CancellationError() }
        cartSync.refresher = refresher
        let context = ReloadCountingContext()
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync, context: context)

        let outcome = await cartSync.syncCart(reason: .pull)
        context.applyResult(await coordinator.syncCart(reason: .pull))

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(context.syncState, .synchronized, "A cancelled sync leaves the state alone")
        XCTAssertTrue(context.syncAlerts.isEmpty)
    }
}

/// Counts the reload passes the coordinator runs and applies sync results the way the session
/// does, minus the members refresh.
@MainActor
private final class ReloadCountingContext: CloudSyncContext {
    let account: OneCartAccount? = OneCartAccount(id: UUID(), displayName: "Reload")
    var isOnline = true
    var syncState: OneCartSyncState = .synchronized
    private(set) var reloadCount = 0
    private(set) var syncAlerts: [String] = []

    func applyCloudSyncEvent(_: CloudSyncEvent) {}

    func applyResult(_ result: CloudSyncResult?) {
        switch result {
        case .synced:
            syncState = isOnline ? .synchronized : .offline
        case let .failed(message, presentsAlert):
            syncState = .failed
            if presentsAlert {
                syncAlerts.append(message)
            }
        case nil:
            break
        }
    }

    func softRefreshCartProducts() {}

    func runCloudImportPass(for _: OneCartAccount) async {
        reloadCount += 1
    }
}
