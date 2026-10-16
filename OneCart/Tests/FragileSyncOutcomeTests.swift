import CoreData
@testable import OneCart
import XCTest

@MainActor
final class FragileSyncOutcomeTests: XCTestCase {
    func test_REQ_SYNC_010_syncCartPullFailureSetsFailedState() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        let account = OneCartAccount(id: UUID(), displayName: "Sync")
        try session.bootstrapTestingSession(account: account)

        let refresher = ScriptedCartRefresher {
            throw NSError(
                domain: "FragileSync",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "refresh exploded"]
            )
        }
        session.cartSync.refresher = refresher

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

    func test_REQ_SYNC_010_syncCartAppearFailureDoesNotPresentAlert() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: OneCartAccount(id: UUID(), displayName: "Sync"))

        let refresher = ScriptedCartRefresher {
            throw NSError(
                domain: "FragileSync",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "appear refresh failed"]
            )
        }
        session.cartSync.refresher = refresher

        await session.syncCart(reason: .appear)

        XCTAssertEqual(session.syncState, .failed)
        XCTAssertEqual(session.lastSyncError, "appear refresh failed")
        XCTAssertNil(session.alertMessage)
    }

    func test_REQ_SYNC_010_syncCartSuccessSetsSynchronized() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: OneCartAccount(id: UUID(), displayName: "Sync"))
        let refresher = ScriptedCartRefresher()
        session.cartSync.refresher = refresher

        await session.syncCart(reason: .pull)

        XCTAssertEqual(session.syncState, .synchronized)
        XCTAssertNil(session.lastSyncError)
    }

    func testSyncCartCoalescesWithoutCancellingInFlight() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let firstSuspended = expectation(description: "First refresh is suspended")
        let secondRequested = expectation(description: "Second sync is requested while the first is in flight")
        var release: CheckedContinuation<Void, Never>?
        var refreshCount = 0
        var firstReturned = false
        var firstRefreshWasCancelled = true
        var firstReturnedBeforeSecondRefresh = true
        let refresher = ScriptedCartRefresher {
            refreshCount += 1
            if refreshCount > 1 { firstReturnedBeforeSecondRefresh = firstReturned }
            guard refreshCount == 1 else { return }
            await withCheckedContinuation { continuation in
                release = continuation
                firstSuspended.fulfill()
            }
            firstRefreshWasCancelled = Task.isCancelled
        }
        cartSync.refresher = refresher

        let first = Task {
            defer { firstReturned = true }
            return await cartSync.syncCart(reason: .cloudImport)
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

        XCTAssertEqual([outcomes.0, outcomes.1], [.succeeded, .succeeded])
        XCTAssertFalse(firstRefreshWasCancelled, "The in-flight refresh must not be cancelled by the second request")
        // Sequential syncs would let the first caller return before the second refresh starts.
        XCTAssertFalse(firstReturnedBeforeSecondRefresh, "The pending pull must run inside the first caller's loop")
        XCTAssertEqual(refreshCount, 2)
        XCTAssertEqual(cartSync.contentRevision, 2)
    }

    func test_coalescedPull_whenRefreshFails_returnsFailureToBothCallers() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let sync = CartSyncService(persistence: persistence)
        let started = expectation(description: "First refresh is suspended")
        let secondStarted = expectation(description: "Pull joins the active refresh")
        var release: CheckedContinuation<Void, Never>?
        var calls = 0
        let refresher = ScriptedCartRefresher {
            calls += 1
            if calls == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    started.fulfill()
                }
            }
            throw NSError(domain: "Sync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Import failed"])
        }
        sync.refresher = refresher
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
}

extension FragileSyncOutcomeTests {
    func test_REQ_SYNC_010_secondAppearWithinDebounceIsSkipped() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let clock = TestClock()
        let cartSync = CartSyncService(persistence: persistence, clock: clock.appClock)
        var refreshCount = 0
        let refresher = ScriptedCartRefresher { refreshCount += 1 }
        cartSync.refresher = refresher

        let first = await cartSync.syncCart(reason: .appear)
        clock.advance(by: .seconds(2))
        let second = await cartSync.syncCart(reason: .appear)
        clock.advance(by: .seconds(1))
        let third = await cartSync.syncCart(reason: .appear)

        XCTAssertEqual(first, .succeeded)
        XCTAssertEqual(second, .skippedDebounce)
        XCTAssertEqual(third, .succeeded)
        XCTAssertEqual(refreshCount, 2)
    }

    func test_REQ_SYNC_010_reasonsQueuedDuringASyncRunOnceWithTheHighestRank() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        let firstSuspended = expectation(description: "First refresh is suspended")
        var release: CheckedContinuation<Void, Never>?
        var chromeDuringRefresh: [Bool] = []
        let refresher = ScriptedCartRefresher {
            chromeDuringRefresh.append(cartSync.isCartSyncing)
            if chromeDuringRefresh.count == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    firstSuspended.fulfill()
                }
            }
        }
        cartSync.refresher = refresher

        let first = Task { await cartSync.syncCart(reason: .pull) }
        await fulfillment(of: [firstSuspended], timeout: 5)
        // Same-actor calls queue before they suspend, so both wait once their expectations are met.
        let cloudQueued = expectation(description: "Cloud import is queued")
        let appearQueued = expectation(description: "Appear is queued")
        let cloud = Task {
            cloudQueued.fulfill()
            return await cartSync.syncCart(reason: .cloudImport)
        }
        let appear = Task {
            appearQueued.fulfill()
            return await cartSync.syncCart(reason: .appear, debouncedAppear: false)
        }
        await fulfillment(of: [cloudQueued, appearQueued], timeout: 5)
        release?.resume()
        _ = await (first.value, cloud.value, appear.value)
        // A cloud import outranks an appear and runs without the "Updating…" chrome.
        XCTAssertEqual(chromeDuringRefresh, [true, false])
    }

    func testSoftRefreshCartProductsBumpsRevision() async throws {
        let persistence = makeInMemoryPersistence()
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
        defaults.set(familyID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))
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

    func test_REQ_SYNC_010_cartContentStorePublishesAfterReload() async throws {
        let persistence = makeInMemoryPersistence()
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
        defaults.set(familyID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))
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
