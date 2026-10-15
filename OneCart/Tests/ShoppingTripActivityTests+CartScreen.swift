import Foundation
@testable import OneCart
import Testing

/// The cart screen's control for the shopping-trip Live Activity.
extension ShoppingTripActivityTests {
    @Test("REQ-WIDGET-040: the cart offers the trip only when there is something to buy and it can run")
    func cartOffersTheTripControl() async throws {
        let milk = CartItem.line("Milk", purchased: true)
        let harness = try CartHarness(lines: [milk])
        #expect(!harness.viewModel.showsShoppingTripControl)

        harness.show([.line("Bread"), milk])
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
        let harness = try CartHarness(lines: [.line("Milk")])

        await harness.viewModel.toggleShoppingTrip()
        #expect(harness.trip.startCount == 1)
        #expect(harness.viewModel.isShoppingTripActive)

        await harness.viewModel.toggleShoppingTrip()
        #expect(harness.trip.endCount == 1)
        #expect(!harness.viewModel.isShoppingTripActive)
    }
}
