import Foundation

extension AppSession: ShoppingTripControlling {
    var isShoppingTripActive: Bool {
        shoppingTrip.isActive
    }

    var areShoppingTripsAvailable: Bool {
        shoppingTrip.isAvailable
    }

    /// Starts the trip from the cart the widgets show (REQ-WIDGET-040); a refusal surfaces
    /// as a system alert (REQ-SHELL-050).
    func startShoppingTrip() async {
        guard isReady, canEdit else { return }
        do {
            try await beginShoppingTrip()
            CartHaptics.success()
        } catch {
            presentAlert(error.localizedDescription, kind: .error)
        }
    }

    func endShoppingTrip() async {
        await shoppingTrip.end().value
    }

    func endShoppingTripWithoutAccount() {
        shoppingTrip.end()
    }
}
