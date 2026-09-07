import SwiftUI
import UIKit

public enum AppAccentColor: String, CaseIterable, Identifiable {
    case emerald
    case ocean
    case sunset
    case berry
    case coral

    public var id: String {
        rawValue
    }

    public var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .emerald: "accent.emerald"
        case .ocean: "accent.ocean"
        case .sunset: "accent.sunset"
        case .berry: "accent.berry"
        case .coral: "accent.coral"
        }
    }

    public var title: String {
        switch self {
        case .emerald: String(localized: "accent.emerald")
        case .ocean: String(localized: "accent.ocean")
        case .sunset: String(localized: "accent.sunset")
        case .berry: String(localized: "accent.berry")
        case .coral: String(localized: "accent.coral")
        }
    }

    public var swatchColor: Color {
        Color(red: primaryRGB.light.0 / 255, green: primaryRGB.light.1 / 255, blue: primaryRGB.light.2 / 255)
    }

    public var primaryRGB: (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .emerald:
            ((52, 120, 91), (62, 147, 112))
        case .ocean:
            ((34, 110, 205), (55, 135, 235))
        case .sunset:
            ((220, 100, 35), (240, 120, 50))
        case .berry:
            ((140, 65, 170), (165, 90, 195))
        case .coral:
            ((225, 75, 85), (245, 95, 105))
        }
    }

    public var primaryStrongRGB: (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .emerald:
            ((40, 95, 71), (46, 110, 83))
        case .ocean:
            ((25, 85, 165), (40, 105, 190))
        case .sunset:
            ((175, 75, 25), (195, 90, 35))
        case .berry:
            ((110, 48, 135), (130, 68, 155))
        case .coral:
            ((180, 55, 65), (200, 70, 80))
        }
    }

    public var primaryAccentRGB: (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .emerald:
            ((40, 95, 71), (116, 199, 159))
        case .ocean:
            ((25, 85, 165), (110, 175, 255))
        case .sunset:
            ((175, 75, 25), (255, 155, 90))
        case .berry:
            ((110, 48, 135), (205, 135, 235))
        case .coral:
            ((180, 55, 65), (255, 140, 148))
        }
    }

    public var primarySoftRGB: (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .emerald:
            ((225, 239, 231), (30, 51, 41))
        case .ocean:
            ((225, 238, 252), (25, 42, 65))
        case .sunset:
            ((253, 238, 226), (60, 35, 20))
        case .berry:
            ((244, 232, 248), (48, 28, 58))
        case .coral:
            ((253, 232, 234), (58, 26, 28))
        }
    }
}
