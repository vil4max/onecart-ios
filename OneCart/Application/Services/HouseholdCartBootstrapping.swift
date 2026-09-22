import Foundation

/// Creates or adopts the one household cart after sign-in (REQ-CART-070, REQ-CART-080).
@MainActor
protocol HouseholdCartBootstrapping: AnyObject {
    var householdCartBootstrapFailed: Bool { get }
    func ensureHouseholdCartIfNeeded() async
    func retryHouseholdCartBootstrap() async
}
