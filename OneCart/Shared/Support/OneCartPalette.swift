import SwiftUI
import UIKit

public enum OneCartPalette {
    /// Filled surfaces that carry white content.
    public static let primary = adaptive(light: (52, 120, 91), dark: (62, 147, 112))
    /// Pressed state of a filled surface.
    public static let primaryStrong = adaptive(light: (40, 95, 71), dark: (46, 110, 83))
    /// Text and glyphs drawn on `background`, `surface` or `primarySoft`.
    public static let primaryAccent = adaptive(light: (40, 95, 71), dark: (116, 199, 159))
    /// Tinted backing for chips and icon tiles.
    public static let primarySoft = adaptive(light: (225, 239, 231), dark: (30, 51, 41))
    public static let background = Color(.systemGroupedBackground)
    public static let surface = Color(.secondarySystemGroupedBackground)
    public static let danger = adaptive(light: (185, 74, 72), dark: (232, 117, 111))

    public static func widgetBackground(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
        } else {
            Color(red: 255 / 255, green: 255 / 255, blue: 255 / 255)
        }
    }

    public static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 62 / 255, green: 147 / 255, blue: 112 / 255)
            : Color(red: 52 / 255, green: 120 / 255, blue: 91 / 255)
    }

    public static func primaryAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 116 / 255, green: 199 / 255, blue: 159 / 255)
            : Color(red: 40 / 255, green: 95 / 255, blue: 71 / 255)
    }

    public static func primarySoft(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 30 / 255, green: 51 / 255, blue: 41 / 255)
            : Color(red: 225 / 255, green: 239 / 255, blue: 231 / 255)
    }

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: components.0 / 255,
                green: components.1 / 255,
                blue: components.2 / 255,
                alpha: 1
            )
        })
    }
}
