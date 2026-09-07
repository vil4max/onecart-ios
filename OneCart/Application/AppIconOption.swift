import SwiftUI
import UIKit

public enum AppIconOption: String, CaseIterable, Identifiable {
    case classic
    case midnight
    case ocean
    case sunset

    public var id: String {
        rawValue
    }

    public var iconName: String? {
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

    public var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .classic: "icon.classic"
        case .midnight: "icon.midnight"
        case .ocean: "icon.ocean"
        case .sunset: "icon.sunset"
        }
    }

    public var title: String {
        switch self {
        case .classic: String(localized: "icon.classic")
        case .midnight: String(localized: "icon.midnight")
        case .ocean: String(localized: "icon.ocean")
        case .sunset: String(localized: "icon.sunset")
        }
    }

    public var previewImageName: String {
        switch self {
        case .classic: "IconPreview-Classic"
        case .midnight: "IconPreview-Midnight"
        case .ocean: "IconPreview-Ocean"
        case .sunset: "IconPreview-Sunset"
        }
    }

    public var previewSymbol: String {
        switch self {
        case .classic: "cart.fill"
        case .midnight: "moon.stars.fill"
        case .ocean: "water.waves"
        case .sunset: "sun.max.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .classic:
            Color(red: 52 / 255, green: 120 / 255, blue: 91 / 255)
        case .midnight:
            Color(red: 30 / 255, green: 30 / 255, blue: 32 / 255)
        case .ocean:
            Color(red: 34 / 255, green: 110 / 255, blue: 205 / 255)
        case .sunset:
            Color(red: 220 / 255, green: 100 / 255, blue: 35 / 255)
        }
    }
}

@MainActor
public enum AppIconManager {
    public static var current: AppIconOption {
        guard UIApplication.shared.supportsAlternateIcons,
              let name = UIApplication.shared.alternateIconName
        else {
            return .classic
        }
        return AppIconOption.allCases.first { $0.iconName == name } ?? .classic
    }

    @discardableResult
    public static func setAlternateIcon(to option: AppIconOption) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        do {
            try await UIApplication.shared.setAlternateIconName(option.iconName)
            return true
        } catch {
            return false
        }
    }
}
