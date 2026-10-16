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
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync, clock: clock.appClock)
        let host = ReloadCountingHost()
        coordinator.bind(host: host)

        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)
        coordinator.cancel()
        // The cancelled task has not run its cleanup yet; the new request must not be dropped.
        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)

        let reloaded = await clock.advanceWhenSleeping(by: .milliseconds(20)) { host.reloadCount >= 1 }
        XCTAssertTrue(reloaded)
        XCTAssertEqual(host.reloadCount, 1)
    }

    func testShorterCloudReloadDelayReschedulesPendingReload() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let refresher = ScriptedCartRefresher()
        cartSync.refresher = refresher
        let clock = TestClock()
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync, clock: clock.appClock)
        let host = ReloadCountingHost()
        coordinator.bind(host: host)
        defer { coordinator.cancel() }

        coordinator.scheduleCloudReload(delayNanoseconds: 30_000_000_000)
        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)

        // Only the shorter delay passes; the 30 s request must not be what runs the reload.
        let reloaded = await clock.advanceWhenSleeping(by: .milliseconds(20)) { host.reloadCount >= 1 }
        XCTAssertTrue(reloaded)
        XCTAssertEqual(host.reloadCount, 1)
    }

    func test_REQ_SHELL_050_foregroundSyncFailureAlertsOnlyAfterHealthyState() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let refresher = ScriptedCartRefresher {
            throw NSError(domain: "Sync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foreground failed"])
        }
        cartSync.refresher = refresher
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync)
        let host = ReloadCountingHost()
        coordinator.bind(host: host)

        host.syncState = .synchronized
        await coordinator.syncCart(reason: .foreground)
        XCTAssertEqual(host.syncAlerts, ["Foreground failed"])
        XCTAssertEqual(host.syncState, .failed)

        await coordinator.syncCart(reason: .foreground)
        XCTAssertEqual(host.syncAlerts.count, 1, "A failure after a failure stays silent")
    }

    func test_REQ_SYNC_010_cancelledRefreshIsReportedAsCancelled() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let refresher = ScriptedCartRefresher { throw CancellationError() }
        cartSync.refresher = refresher
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync)
        let host = ReloadCountingHost()
        coordinator.bind(host: host)

        let outcome = await cartSync.syncCart(reason: .pull)
        await coordinator.syncCart(reason: .pull)

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(host.syncState, .synchronized, "A cancelled sync leaves the state alone")
        XCTAssertTrue(host.syncAlerts.isEmpty)
    }
}

@MainActor
private final class ReloadCountingHost: CloudSyncHost {
    let account: OneCartAccount? = OneCartAccount(id: UUID(), displayName: "Reload")
    var isOnline = true
    var syncState: OneCartSyncState = .synchronized
    private(set) var reloadCount = 0
    private(set) var syncAlerts: [String] = []

    func applySyncState(_ state: OneCartSyncState) {
        syncState = state
    }

    func applyLastSyncError(_: String?) {}

    func presentSyncAlert(_ message: String) {
        syncAlerts.append(message)
    }

    func presentProductionSchemaAlertIfNeeded(_: String) {}

    func drainWidgetPendingToggles() async {}

    func softRefreshCartProducts() {}

    func refreshFamilyMetadata(showErrors _: Bool) async {}

    func offerSharedCartJoinIfNeeded(for _: OneCartAccount) async throws {
        reloadCount += 1
    }

    func userFacingMessage(for error: Error) -> String {
        error.localizedDescription
    }

    func applyConnectivityOnline(_ isOnline: Bool) {
        self.isOnline = isOnline
    }
}
