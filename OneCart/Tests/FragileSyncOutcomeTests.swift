import CoreData
@testable import OneCart
import XCTest

@MainActor
final class FragileSyncOutcomeTests: XCTestCase {
    func testSyncCartPullFailureSetsFailedState() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        let account = OneCartAccount(id: UUID(), displayName: "Sync")
        try session.bootstrapTestingSession(account: account)

        session.cartSync.onHardRefresh = {
            throw NSError(
                domain: "FragileSync",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "refresh exploded"]
            )
        }

        await session.syncCart(reason: .pull)

        XCTAssertEqual(session.syncState, .failed)
        XCTAssertEqual(session.lastSyncError, "refresh exploded")
        XCTAssertEqual(session.alertMessage, "refresh exploded")
        XCTAssertEqual(session.userAlert?.kind, .error)
        XCTAssertNotEqual(
            session.alertMessage,
            RepositoryError.permissionDenied.localizedDescription
        )
    }

    func testSyncCartAppearFailureDoesNotPresentAlert() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: OneCartAccount(id: UUID(), displayName: "Sync"))

        session.cartSync.onHardRefresh = {
            throw NSError(
                domain: "FragileSync",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "appear refresh failed"]
            )
        }

        await session.syncCart(reason: .appear)

        XCTAssertEqual(session.syncState, .failed)
        XCTAssertEqual(session.lastSyncError, "appear refresh failed")
        XCTAssertNil(session.alertMessage)
    }

    func testSyncCartSuccessSetsSynchronized() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: OneCartAccount(id: UUID(), displayName: "Sync"))
        session.cartSync.onHardRefresh = {}

        await session.syncCart(reason: .pull)

        XCTAssertEqual(session.syncState, .synchronized)
        XCTAssertNil(session.lastSyncError)
    }

    func testSyncCartCoalescesWithoutCancellingInFlight() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let firstSuspended = expectation(description: "First refresh is suspended")
        let secondRequested = expectation(description: "Second sync is requested while the first is in flight")
        var release: CheckedContinuation<Void, Never>?
        var refreshCount = 0
        var firstReturned = false
        var firstRefreshWasCancelled = true
        var firstReturnedBeforeSecondRefresh = true
        cartSync.onHardRefresh = {
            refreshCount += 1
            if refreshCount == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    firstSuspended.fulfill()
                }
                firstRefreshWasCancelled = Task.isCancelled
            } else {
                firstReturnedBeforeSecondRefresh = firstReturned
            }
        }

        let first = Task {
            let outcome = await cartSync.syncCart(reason: .cloudImport)
            firstReturned = true
            return outcome
        }
        await fulfillment(of: [firstSuspended], timeout: 5)
        XCTAssertEqual(refreshCount, 1)
        // Same-actor calls do not suspend, so the second request is queued behind the
        // suspended refresh before this test regains the main actor.
        let second = Task {
            secondRequested.fulfill()
            return await cartSync.syncCart(reason: .pull)
        }
        await fulfillment(of: [secondRequested], timeout: 5)
        XCTAssertEqual(refreshCount, 1, "The joined request must not start a parallel refresh")
        release?.resume()
        let outcomes = await (first.value, second.value)

        XCTAssertEqual(outcomes.0, .succeeded)
        XCTAssertEqual(outcomes.1, .succeeded)
        XCTAssertFalse(firstRefreshWasCancelled, "The in-flight refresh must not be cancelled by the second request")
        // Sequential syncs would let the first caller return before the second refresh starts.
        XCTAssertFalse(firstReturnedBeforeSecondRefresh, "The pending pull must run inside the first caller's loop")
        XCTAssertEqual(refreshCount, 2)
        XCTAssertEqual(cartSync.contentRevision, 2)
    }

    func test_coalescedPull_whenRefreshFails_returnsFailureToBothCallers() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let sync = CartSyncService(persistence: persistence)
        let started = expectation(description: "First refresh is suspended")
        let secondStarted = expectation(description: "Pull joins the active refresh")
        var release: CheckedContinuation<Void, Never>?
        var calls = 0
        sync.onHardRefresh = {
            calls += 1
            if calls == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    started.fulfill()
                }
            }
            throw NSError(domain: "Sync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Import failed"])
        }
        let first = Task { await sync.syncCart(reason: .cloudImport) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            secondStarted.fulfill()
            return await sync.syncCart(reason: .pull)
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        release?.resume()
        let outcomes = await (first.value, second.value)
        XCTAssertEqual(outcomes.0, .failed("Import failed"))
        XCTAssertEqual(outcomes.1, .failed("Import failed"))
        XCTAssertEqual(calls, 2)
    }

    func testCloudReloadScheduledRightAfterCancelStillRuns() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        cartSync.onHardRefresh = {}
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync)
        let host = ReloadCountingHost()
        coordinator.bind(host: host)

        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)
        coordinator.cancel()
        // The cancelled task has not run its cleanup yet; the new request must not be dropped.
        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)

        try await waitForReloads(1, on: host)
        XCTAssertEqual(host.reloadCount, 1)
    }

    func testShorterCloudReloadDelayReschedulesPendingReload() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        cartSync.onHardRefresh = {}
        let coordinator = CloudSyncCoordinator(persistence: persistence, cartSync: cartSync)
        let host = ReloadCountingHost()
        coordinator.bind(host: host)
        defer { coordinator.cancel() }

        coordinator.scheduleCloudReload(delayNanoseconds: 30_000_000_000)
        coordinator.scheduleCloudReload(delayNanoseconds: 20_000_000)

        try await waitForReloads(1, on: host)
        XCTAssertEqual(host.reloadCount, 1)
    }

    private func waitForReloads(_ count: Int, on host: ReloadCountingHost) async throws {
        for _ in 0 ..< 100 where host.reloadCount < count {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testSoftRefreshCartProductsBumpsRevision() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Soft")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Корзина",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(familyID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        let list = try XCTUnwrap(session.activeLists.first)
        await session.addProduct(to: list, draft: productDraft(name: "Молоко"))
        let before = session.contentRevision

        session.softRefreshCartProducts()

        XCTAssertEqual(session.contentRevision, before + 1)
        XCTAssertEqual(session.products.first?.displayName, "Молоко")
    }

    func testCartContentStorePublishesAfterReload() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Content")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Корзина",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(familyID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        let list = try XCTUnwrap(session.activeLists.first)
        await session.addProduct(to: list, draft: productDraft(name: "Хлеб"))
        XCTAssertFalse(session.products.isEmpty)

        try CartSyncService.resetViewContextAndRefetch(persistence: persistence) {
            try session.cartContent.reloadContent(familySpaceID: familyID)
        }
        XCTAssertFalse(session.products.isEmpty)
        XCTAssertEqual(session.products.first?.displayName, "Хлеб")
    }
}

@MainActor
private final class ReloadCountingHost: CloudSyncHost {
    let account: OneCartAccount? = OneCartAccount(id: UUID(), displayName: "Reload")
    var isOnline = true
    var syncState: OneCartSyncState = .synchronized
    private(set) var reloadCount = 0

    func applySyncState(_ state: OneCartSyncState) {
        syncState = state
    }

    func applyLastSyncError(_: String?) {}

    func presentSyncAlert(_: String) {}

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
