import Foundation
@testable import OneCart

@MainActor
final class FakeAppIconSwitcher: AppIconSwitching {
    var requestedIcons: [AppIconOption] = []
    var result = true

    func setAlternateIcon(to option: AppIconOption) async -> Bool {
        requestedIcons.append(option)
        return result
    }
}
