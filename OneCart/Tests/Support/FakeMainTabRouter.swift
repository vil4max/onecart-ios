import Foundation
@testable import OneCart

@MainActor
final class FakeMainTabRouter: MainTabRouting {
    var preferredMainTab: MainTab?
    var showFamilyManagementCount = 0
    var clearPreferredMainTabCount = 0

    func showFamilyManagement() {
        showFamilyManagementCount += 1
        preferredMainTab = .account
    }

    func clearPreferredMainTab() {
        clearPreferredMainTabCount += 1
        preferredMainTab = nil
    }
}
