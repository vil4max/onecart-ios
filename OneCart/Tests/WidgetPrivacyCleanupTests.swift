@testable import OneCart
import Synchronization
import XCTest

@MainActor
private final class PurchaseReturnFlag {
    var value = false
}

@MainActor
final class WidgetPrivacyCleanupTests: XCTestCase {
    func test_clear_removesWidgetSnapshotAndPendingPurchases() throws {
        let fixture = try makeWidgetStore()
        fixture.store.save(snapshot: .placeholder)
        try fixture.store.enqueuePurchase(
            WidgetPurchaseRequest(
                accountID: UUID(), familyID: UUID(), productID: UUID(), isPurchased: true
            ))

        try fixture.store.clear()

        XCTAssertTrue(fixture.store.loadSnapshot()?.isEmpty ?? true)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_REQ_AUTH_060_signOut_clearsWidgetDataAndRejectsLateWidgetAction() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request()
        try fixture.store.enqueuePurchase(request)
        fixture.session.updateWidgetSnapshot()
        XCTAssertFalse(try XCTUnwrap(fixture.store.loadSnapshot()).isEmpty)

        fixture.session.signOut()

        XCTAssertNil(fixture.session.account)
        XCTAssertTrue(fixture.store.loadSnapshot()?.isEmpty ?? true)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
        do {
            try await fixture.session.performWidgetPurchase(request)
            XCTFail("A stale widget must not enqueue purchases after sign-out")
        } catch {
            XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
        }
    }

    func test_REQ_AUTH_060_signOut_removesActivitySnapshotsAndICloudIdentity() async throws {
        let defaults = try makeDefaults()
        let session = try makeTestSession(defaults: defaults)
        session.account = OneCartAccount(id: UUID(), displayName: "Alex")
        let snapshotKey = "onecart.cart-activity-snapshot.\(UUID().uuidString)"
        defaults.set(Data("[{\"name\":\"Milk\"}]".utf8), forKey: snapshotKey)
        _ = session.backend.userRecordNameCache.withLock { $0.store("_previousUser", readUnder: $0.generation) }
        session.knownUserRecordName = ("_previousUser", session.cloudUserIdentity.identityGeneration)

        session.signOut()

        XCTAssertNil(session.account)
        XCTAssertNil(defaults.object(forKey: snapshotKey), "item and member names must not survive sign-out")
        XCTAssertNil(session.backend.userRecordNameCache.withLock { $0.recordName })
        XCTAssertNil(session.knownUserRecordName)
    }

    func test_REQ_WIDGET_050_purchaseFromTheTripReachesItAndFinishesIt() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        fixture.session.updateWidgetSnapshot()

        await fixture.session.startShoppingTrip()
        XCTAssertTrue(fixture.session.isShoppingTripActive)
        XCTAssertEqual(backend.requested.first?.state.remainingCount, 1)
        XCTAssertEqual(backend.requested.first?.attributes.familyID, fixture.familyID)

        // The Live Activity's check button runs the same intent path as the widget.
        try await fixture.session.performWidgetPurchase(fixture.request())
        await fixture.session.shoppingTrip.settle()

        XCTAssertFalse(fixture.session.isShoppingTripActive)
        XCTAssertEqual(backend.ended.count, 1)
        XCTAssertEqual(backend.ended.first?.state?.isAllPurchased, true)
    }

    func test_REQ_WIDGET_050_lockScreenCheck_updatesTheTripBeforeReturning() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        fixture.session.updateWidgetSnapshot()
        await fixture.session.startShoppingTrip()

        // The system redraws the card when the intent returns, so the trip's own update
        // must finish first. A held ActivityKit call shows whether the intent waits for it.
        backend.holdsEnds = true
        // The purchase saves on a Core Data background context before it reaches the trip, so
        // main-actor yields alone can run out first on a loaded CI runner.
        let endHeld = expectation(description: "The trip's end reached ActivityKit")
        backend.onHeldEnd = { endHeld.fulfill() }
        let returned = PurchaseReturnFlag()
        let purchase = Task {
            try await fixture.session.performWidgetPurchase(fixture.request())
            returned.value = true
        }
        await fulfillment(of: [endHeld], timeout: 5)
        await backend.yield { returned.value }
        XCTAssertEqual(backend.heldEnds, 1)
        XCTAssertFalse(returned.value, "The check returned before the trip was updated")

        backend.releaseEnds()
        try await purchase.value
        XCTAssertEqual(backend.ended.map(\.state?.isAllPurchased), [true])
        XCTAssertFalse(fixture.session.isShoppingTripActive)
    }

    func test_REQ_WIDGET_060_signOut_endsTheShoppingTrip() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        await fixture.session.startShoppingTrip()
        XCTAssertEqual(backend.running.count, 1)

        fixture.session.signOut()
        await fixture.session.shoppingTrip.settle()

        XCTAssertFalse(fixture.session.isShoppingTripActive)
        XCTAssertTrue(backend.running.isEmpty)
        XCTAssertEqual(backend.ended.first?.dismissal, .immediate)
    }

    func test_REQ_WIDGET_060_signOutWhileTheTripIsStarting_endsIt() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        await fixture.session.startShoppingTrip()
        // A held end keeps the next start queued in the trip controller while no trip is active.
        backend.holdsEnds = true
        fixture.session.shoppingTrip.end()
        await backend.yield { backend.heldEnds == 1 }
        let starting = Task { await fixture.session.startShoppingTrip() }
        await backend.yield { false }
        XCTAssertFalse(fixture.session.isShoppingTripActive)

        fixture.session.signOut()
        backend.releaseEnds()
        await starting.value
        await fixture.session.shoppingTrip.settle()

        XCTAssertEqual(backend.requested.count, 2)
        XCTAssertTrue(backend.running.isEmpty)
        XCTAssertFalse(fixture.session.isShoppingTripActive)
    }

    /// A startup that fails (iCloud briefly unavailable, a store-load error) signs nobody out,
    /// so the trip stays for the retry that follows; REQ-WIDGET-060 ends it only on sign-out,
    /// deletion or a change of account or cart.
    func test_REQ_WIDGET_060_failedStartup_keepsTheRunningTrip() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        await fixture.session.startShoppingTrip()
        XCTAssertEqual(backend.running.count, 1)

        fixture.session.clearBootstrapAccount()
        await fixture.session.shoppingTrip.settle()

        XCTAssertEqual(backend.running.count, 1)
        XCTAssertTrue(backend.ended.isEmpty)
    }

    func test_REQ_WIDGET_060_launchWithoutSignedInAccount_endsTheLeftoverTrip() async throws {
        let leftover = ShoppingTripActivityRecord(id: "leftover", accountID: UUID(), familyID: UUID())
        let backend = FakeShoppingTripBackend(running: [leftover])
        let fixture = try await makeWidgetSession(started: false, shoppingTripBackend: backend)
        fixture.session.clearStoredAppleCredential()

        await fixture.session.start()
        await fixture.session.shoppingTrip.settle()

        XCTAssertTrue(fixture.session.needsWelcome)
        XCTAssertTrue(backend.running.isEmpty)
        XCTAssertEqual(backend.ended.map(\.id), ["leftover"])
        XCTAssertFalse(fixture.session.isShoppingTripActive)
    }

    func test_REQ_AUTH_070_deleteAccount_clearsWidgetSnapshotAndPendingPurchases() async throws {
        let fixture = try await makeWidgetSession()
        try fixture.store.enqueuePurchase(fixture.request())
        fixture.session.updateWidgetSnapshot()
        XCTAssertFalse(try XCTUnwrap(fixture.store.loadSnapshot()).isEmpty)

        await fixture.session.deleteAccount()

        XCTAssertNil(fixture.session.account)
        XCTAssertTrue(fixture.store.loadSnapshot()?.isEmpty ?? true)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }
}
