import Foundation

/// Cross-tab navigation requests: the cart asks for Settings; the tab bar consumes the request.
@MainActor
protocol MainTabRouting: AnyObject {
    var preferredMainTab: MainTab? { get }
    func showFamilyManagement()
    func clearPreferredMainTab()
}
