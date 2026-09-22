import Foundation

/// The shopping trip on the Lock Screen and in the Dynamic Island, as the cart screen drives it.
@MainActor
protocol ShoppingTripControlling: AnyObject {
    var isShoppingTripActive: Bool { get }
    /// False when Live Activities are turned off for OneCart in Settings.
    var areShoppingTripsAvailable: Bool { get }
    func startShoppingTrip() async
    func endShoppingTrip() async
}
