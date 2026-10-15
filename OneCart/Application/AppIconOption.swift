import SwiftUI
import UIKit

enum AppIconOption: String, CaseIterable, Identifiable {
    case classic
    case midnight
    case ocean
    case sunset

    var id: String {
        rawValue
    }

    var iconName: String? {
        switch self {
        case .classic:
            nil
        case .midnight:
            "AppIcon-Midnight"
        case .ocean:
            "AppIcon-Ocean"
        case .sunset:
            "AppIcon-Sunset"
        }
    }

    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .classic: "icon.classic"
        case .midnight: "icon.midnight"
        case .ocean: "icon.ocean"
        case .sunset: "icon.sunset"
        }
    }

    var title: String {
        switch self {
        case .classic: String(localized: "icon.classic")
        case .midnight: String(localized: "icon.midnight")
        case .ocean: String(localized: "icon.ocean")
        case .sunset: String(localized: "icon.sunset")
        }
    }

    var previewImageName: String {
        switch self {
        case .classic: "IconPreview-Classic"
        case .midnight: "IconPreview-Midnight"
        case .ocean: "IconPreview-Ocean"
        case .sunset: "IconPreview-Sunset"
        }
    }

    /// The app's accent follows the chosen icon; Midnight's amber check reads as Sunset.
    var accent: AppAccentColor {
        switch self {
        case .classic: .emerald
        case .midnight: .sunset
        case .ocean: .ocean
        case .sunset: .sunset
        }
    }
}

@MainActor
enum AppIconManager {
    @discardableResult
    static func setAlternateIcon(to option: AppIconOption) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        do {
            try await UIApplication.shared.setAlternateIconName(option.iconName)
            return true
        } catch {
            return false
        }
    }
}

/// Switches the home-screen icon; the view model depends on this so tests never touch `UIApplication`.
@MainActor
protocol AppIconSwitching {
    @discardableResult
    func setAlternateIcon(to option: AppIconOption) async -> Bool
}

struct SystemAppIconSwitcher: AppIconSwitching {
    func setAlternateIcon(to option: AppIconOption) async -> Bool {
        await AppIconManager.setAlternateIcon(to: option)
    }
}
