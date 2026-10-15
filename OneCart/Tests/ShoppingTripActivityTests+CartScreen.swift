import Foundation
@testable import OneCart
import Testing

/// The cart screen's control for the shopping-trip Live Activity.
extension ShoppingTripActivityTests {
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
