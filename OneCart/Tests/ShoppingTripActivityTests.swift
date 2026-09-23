import Foundation
@testable import OneCart
import Testing

/// The shopping-trip Live Activity: what it shows, when it starts, follows and ends.
@MainActor
@Suite("ShoppingTripActivityTests")
struct ShoppingTripActivityTests {
    private nonisolated static let accountID = UUID()
    private nonisolated static let familyID = UUID()
    private nonisolated static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private nonisolated static func item(_ name: String, purchased: Bool = false) -> WidgetItemSnapshot {
        WidgetItemSnapshot(
            id: UUID(),
            name: name,
            isPurchased: purchased,
            categoryRaw: ProductCategory.inferred(from: name).rawValue
        )
    }

    private nonisolated static func snapshot(
        title: String = "Family",
        items: [WidgetItemSnapshot],
        totalCount: Int? = nil,
        purchasedCount: Int? = nil,
        accountID: UUID? = ShoppingTripActivityTests.accountID,
        familyID: UUID? = ShoppingTripActivityTests.familyID
    ) -> WidgetCartSnapshot {
        WidgetCartSnapshot(
            cartTitle: title,
            totalCount: totalCount ?? items.count,
            purchasedCount: purchasedCount ?? items.filter(\.isPurchased).count,
            isSyncing: false,
            lastUpdated: fixedNow,
            familyMemberCount: 2,
            accentColorRaw: AppAccentColor.emerald.rawValue,
            accountID: accountID,
            familyID: familyID,
            items: items
        )
    }

    private static let shoppingSnapshot = snapshot(items: [
        item("Milk"), item("Bread"), item("Eggs"), item("Cheese"), item("Apples", purchased: true),
    ])

    private static let allBoughtSnapshot = snapshot(items: shoppingSnapshot.items.map { item in
        var bought = item
        bought.isPurchased = true
        return bought
    })

    private static func makeController(
        backend: FakeShoppingTripBackend = FakeShoppingTripBackend()
    ) -> (ShoppingTripActivityController, FakeShoppingTripBackend) {
        (ShoppingTripActivityController(backend: backend, now: { fixedNow }), backend)
    }

    // MARK: - Content

    @Test("REQ-WIDGET-040: the trip shows the cart's progress and its first three lines to buy")
    func contentStateMirrorsTheSnapshot() {
        let state = ShoppingTripAttributes.ContentState(snapshot: Self.shoppingSnapshot)
        #expect(state.cartTitle == "Family")
        #expect(state.purchasedCount == 1)
        #expect(state.totalCount == 5)
        #expect(state.remainingCount == 4)
        #expect(state.nextItems.map(\.name) == ["Milk", "Bread", "Eggs"])
        #expect(state.accentColor == .emerald)
        #expect(!state.isAllPurchased)
    }

    // MARK: - Start

    @Test("REQ-WIDGET-040: starting requests one activity for this account and cart")
    func startRequestsOneActivity() async throws {
        let (controller, backend) = Self.makeController()
        try await controller.start(with: Self.shoppingSnapshot)
        try await controller.start(with: Self.shoppingSnapshot)

        #expect(backend.requested.count == 1)
        #expect(backend.requested.first?.attributes.accountID == Self.accountID)
        #expect(backend.requested.first?.attributes.familyID == Self.familyID)
        #expect(backend.requested.first?.state.nextItems.count == 3)
        #expect(controller.isActive)
    }

    @Test("REQ-WIDGET-040: a trip needs lines to buy, a signed-in cart and Live Activities turned on")
    func startIsRefusedWithoutSomethingToFollow() async {
        let (controller, backend) = Self.makeController()
        let allBought = Self.snapshot(items: [Self.item("Milk", purchased: true)])
        await #expect(throws: ShoppingTripError.nothingToBuy) {
            try await controller.start(with: allBought)
        }
        await #expect(throws: ShoppingTripError.nothingToBuy) {
            try await controller.start(with: Self.snapshot(items: []))
        }
        await #expect(throws: ShoppingTripError.unavailable) {
            try await controller.start(with: Self.snapshot(items: [Self.item("Milk")], familyID: nil))
        }
        backend.areActivitiesEnabled = false
        await #expect(throws: ShoppingTripError.unavailable) {
            try await controller.start(with: Self.shoppingSnapshot)
        }
        backend.areActivitiesEnabled = true
        backend.requestError = CocoaError(.featureUnsupported)
        await #expect(throws: ShoppingTripError.unavailable) {
            try await controller.start(with: Self.shoppingSnapshot)
        }
        #expect(backend.requested.isEmpty)
        #expect(!controller.isActive)
    }

    // MARK: - Follow

    @Test("REQ-WIDGET-050: the trip follows the cart and skips updates that change nothing")
    func syncUpdatesOnlyOnChange() async throws {
        let (controller, backend) = Self.makeController()
        controller.sync(with: Self.shoppingSnapshot)
        await controller.settle()
        #expect(backend.updates.isEmpty)

        try await controller.start(with: Self.shoppingSnapshot)
        controller.sync(with: Self.shoppingSnapshot)
        await controller.settle()
        #expect(backend.updates.isEmpty)

        var items = Self.shoppingSnapshot.items
        items[0].isPurchased = true
        controller.sync(with: Self.snapshot(title: "Weekend", items: items))
        await controller.settle()
        #expect(backend.updates.count == 1)
        #expect(backend.updates.first?.state.cartTitle == "Weekend")
        #expect(backend.updates.first?.state.purchasedCount == 2)
        #expect(backend.updates.first?.state.nextItems.map(\.name) == ["Bread", "Eggs", "Cheese"])
    }

    @Test("REQ-WIDGET-050: a cart change while the trip is starting still reaches it")
    func syncDuringStartReachesTheTrip() async throws {
        let (controller, backend) = Self.makeController()
        try await controller.start(with: Self.shoppingSnapshot)
        // A held end keeps the next start queued while no trip is active.
        backend.holdsEnds = true
        controller.end()
        await backend.yield { backend.heldEnds == 1 }
        let starting = Task { try await controller.start(with: Self.shoppingSnapshot) }
        await backend.yield { false }
        #expect(!controller.isActive)

        var items = Self.shoppingSnapshot.items
        items[0].isPurchased = true
        controller.sync(with: Self.snapshot(items: items))
        backend.releaseEnds()
        try await starting.value
        await controller.settle()

        #expect(backend.requested.count == 2)
        #expect(backend.updates.map(\.state.purchasedCount) == [2])
    }

    @Test("REQ-WIDGET-050: a relaunched app adopts its running trip and ends leftovers")
    func relaunchAdoptsRunningTrip() async {
        let kept = ShoppingTripActivityRecord(id: "kept", accountID: Self.accountID, familyID: Self.familyID)
        let leftover = ShoppingTripActivityRecord(id: "leftover", accountID: Self.accountID, familyID: Self.familyID)
        let (controller, backend) = Self.makeController(backend: FakeShoppingTripBackend(running: [kept, leftover]))
        controller.sync(with: Self.shoppingSnapshot)
        await controller.settle()

        #expect(controller.activeTrip == kept)
        #expect(backend.ended.map(\.id) == ["leftover"])
        #expect(backend.ended.first?.dismissal == .immediate)
    }

    @Test("REQ-WIDGET-050: a relaunched app adopts only the trip of the signed-in account and active cart")
    func relaunchAdoptsOnlyTheSignedInCartsTrip() async {
        let otherAccount = ShoppingTripActivityRecord(id: "a-other-account", accountID: UUID(), familyID: Self.familyID)
        let otherCart = ShoppingTripActivityRecord(id: "b-other-cart", accountID: Self.accountID, familyID: UUID())
        let kept = ShoppingTripActivityRecord(id: "c-kept", accountID: Self.accountID, familyID: Self.familyID)
        let backend = FakeShoppingTripBackend(running: [otherAccount, otherCart, kept])
        let (controller, _) = Self.makeController(backend: backend)

        controller.sync(with: Self.shoppingSnapshot)
        await controller.settle()

        #expect(controller.activeTrip == kept)
        #expect(backend.running == [kept])
        #expect(Set(backend.ended.map(\.id)) == [otherAccount.id, otherCart.id])
        #expect(backend.ended.allSatisfy { $0.dismissal == .immediate })
    }

    // MARK: - End

    @Test("REQ-WIDGET-060: checking the last line shows the finished trip, then dismisses it")
    func allPurchasedEndsWithDelayedDismissal() async throws {
        let (controller, backend) = Self.makeController()
        try await controller.start(with: Self.shoppingSnapshot)
        let items = Self.shoppingSnapshot.items.map { item -> WidgetItemSnapshot in
            var bought = item
            bought.isPurchased = true
            return bought
        }
        controller.sync(with: Self.snapshot(items: items))
        await controller.settle()

        let ended = try #require(backend.ended.first)
        #expect(ended.state?.isAllPurchased == true)
        #expect(ended.dismissal == .after(Self.fixedNow.addingTimeInterval(
            ShoppingTripActivityController.completedDismissalDelay
        )))
        #expect(!controller.isActive)
    }

    @Test("REQ-WIDGET-060: stop on the finished trip dismisses it at once")
    func stopDismissesTheFinishedTrip() async throws {
        let (controller, backend) = Self.makeController()
        try await controller.start(with: Self.shoppingSnapshot)
        let id = try #require(controller.activeTrip?.id)
        controller.sync(with: Self.allBoughtSnapshot)
        await controller.settle()
        #expect(backend.shownIDs == [id])

        await controller.end().value

        #expect(backend.ended.last == .init(id: id, state: nil, dismissal: .immediate))
        #expect(backend.shownIDs.isEmpty)
    }

    @Test("REQ-WIDGET-060: starting again while the finished trip is shown leaves one card")
    func restartReplacesTheFinishedTrip() async throws {
        let (controller, backend) = Self.makeController()
        try await controller.start(with: Self.shoppingSnapshot)
        controller.sync(with: Self.allBoughtSnapshot)
        await controller.settle()

        // A line is un-checked within the five minutes and the trip starts again.
        try await controller.start(with: Self.shoppingSnapshot)

        let id = try #require(controller.activeTrip?.id)
        #expect(backend.shownIDs == [id])
    }

    @Test("REQ-WIDGET-060: another cart, another account or an emptied cart ends the trip at once")
    func lostCartEndsImmediately() async throws {
        let changes = [
            Self.snapshot(items: [Self.item("Milk")], familyID: UUID()),
            Self.snapshot(items: [Self.item("Milk")], accountID: nil, familyID: nil),
            Self.snapshot(items: []),
        ]
        for change in changes {
            let (controller, backend) = Self.makeController()
            try await controller.start(with: Self.shoppingSnapshot)
            controller.sync(with: change)
            await controller.settle()
            #expect(backend.ended.map(\.dismissal) == [.immediate])
            #expect(backend.running.isEmpty)
            #expect(!controller.isActive)
        }
    }

    @Test("REQ-WIDGET-060: the stop button ends the trip, and a Lock Screen dismissal is noticed")
    func userEndsTheTrip() async throws {
        let (controller, backend) = Self.makeController()
        try await controller.start(with: Self.shoppingSnapshot)
        await controller.end().value
        #expect(backend.ended.map(\.dismissal) == [.immediate])
        #expect(!controller.isActive)

        try await controller.start(with: Self.shoppingSnapshot)
        let id = try #require(controller.activeTrip?.id)
        backend.dismissFromLockScreen(id: id)
        controller.sync(with: Self.shoppingSnapshot)
        await controller.settle()
        #expect(!controller.isActive)
        #expect(backend.updates.isEmpty)
    }

    // MARK: - Cart screen

    @Test("REQ-WIDGET-040: the cart offers the trip only when there is something to buy and it can run")
    func cartOffersTheTripControl() async throws {
        let fixture = try await CartFixture.make()
        _ = try await fixture.addProduct(named: "Milk", purchased: true)
        let harness = try CartHarness(fixture: fixture)
        #expect(!harness.viewModel.showsShoppingTripControl)

        _ = try await fixture.addProduct(named: "Bread")
        harness.state.productsByListID[fixture.listID] = try fixture.products
        #expect(harness.viewModel.showsShoppingTripControl)

        harness.trip.areShoppingTripsAvailable = false
        #expect(!harness.viewModel.showsShoppingTripControl)
        harness.trip.areShoppingTripsAvailable = true
        harness.state.canEdit = false
        #expect(!harness.viewModel.showsShoppingTripControl)

        // A running trip can always be stopped.
        harness.trip.isShoppingTripActive = true
        #expect(harness.viewModel.showsShoppingTripControl)
    }

    @Test("REQ-WIDGET-060: the cart control starts the trip, then stops it")
    func cartControlTogglesTheTrip() async throws {
        let fixture = try await CartFixture.make()
        _ = try await fixture.addProduct(named: "Milk")
        let harness = try CartHarness(fixture: fixture)

        await harness.viewModel.toggleShoppingTrip()
        #expect(harness.trip.startCount == 1)
        #expect(harness.viewModel.isShoppingTripActive)

        await harness.viewModel.toggleShoppingTrip()
        #expect(harness.trip.endCount == 1)
        #expect(!harness.viewModel.isShoppingTripActive)
    }
}
