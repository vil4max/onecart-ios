import Foundation

/// Session-level alerts shown by the root screen (REQ-SHELL-050) and the cart.
@MainActor
protocol AlertPresenting: AnyObject {
    var userAlert: UserAlert? { get }
    var sharedCartRemovedMessage: String? { get }
    func dismissAlert()
    func dismissSharedCartRemovedMessage()
}
