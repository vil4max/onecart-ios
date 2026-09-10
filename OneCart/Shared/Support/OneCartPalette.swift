import SwiftUI
import UIKit

public enum OneCartPalette {
    /// Active accent color across the app.
    public static var currentAccent: AppAccentColor = {
        if let raw = OneCartAppGroup.defaults?.string(forKey: "onecart.accent-color"),
           let accent = AppAccentColor(rawValue: raw)
        {
            return accent
        }
        if let raw = UserDefaults.standard.string(forKey: "onecart.accent-color"),
           let accent = AppAccentColor(rawValue: raw)
        {
            return accent
        }
        return .emerald
    }()

    /// Filled surfaces that carry white content.
    public static var primary: Color {
        primary()
    }

    public static func primary(for scheme: ColorScheme? = nil, accent: AppAccentColor? = nil) -> Color {
        let active = accent ?? currentAccent
        if let scheme {
            let rgb = scheme == .dark ? active.primaryRGB.dark : active.primaryRGB.light
            return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
        }
        if let accent {
            return adaptive(light: accent.primaryRGB.light, dark: accent.primaryRGB.dark)
        }
        return adaptiveDynamic(
            light: { $0.primaryRGB.light },
            dark: { $0.primaryRGB.dark }
        )
    }

    /// Pressed state of a filled surface.
    public static var primaryStrong: Color {
        primaryStrong()
    }

    public static func primaryStrong(for scheme: ColorScheme? = nil, accent: AppAccentColor? = nil) -> Color {
        let active = accent ?? currentAccent
        if let scheme {
            let rgb = scheme == .dark ? active.primaryStrongRGB.dark : active.primaryStrongRGB.light
            return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
        }
        if let accent {
            return adaptive(light: accent.primaryStrongRGB.light, dark: accent.primaryStrongRGB.dark)
        }
        return adaptiveDynamic(
            light: { $0.primaryStrongRGB.light },
            dark: { $0.primaryStrongRGB.dark }
        )
    }

    /// Text and glyphs drawn on `background`, `surface` or `primarySoft`.
    public static var primaryAccent: Color {
        primaryAccent()
    }

    public static func primaryAccent(for scheme: ColorScheme? = nil, accent: AppAccentColor? = nil) -> Color {
        let active = accent ?? currentAccent
        if let scheme {
            let rgb = scheme == .dark ? active.primaryAccentRGB.dark : active.primaryAccentRGB.light
            return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
        }
        if let accent {
            return adaptive(light: accent.primaryAccentRGB.light, dark: accent.primaryAccentRGB.dark)
        }
        return adaptiveDynamic(
            light: { $0.primaryAccentRGB.light },
            dark: { $0.primaryAccentRGB.dark }
        )
    }

    /// Tinted backing for chips and icon tiles.
    public static var primarySoft: Color {
        primarySoft()
    }

    public static func primarySoft(for scheme: ColorScheme? = nil, accent: AppAccentColor? = nil) -> Color {
        let active = accent ?? currentAccent
        if let scheme {
            let rgb = scheme == .dark ? active.primarySoftRGB.dark : active.primarySoftRGB.light
            return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
        }
        if let accent {
            return adaptive(light: accent.primarySoftRGB.light, dark: accent.primarySoftRGB.dark)
        }
        return adaptiveDynamic(
            light: { $0.primarySoftRGB.light },
            dark: { $0.primarySoftRGB.dark }
        )
    }

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

    private static func adaptiveDynamic(
        light: @escaping (AppAccentColor) -> (CGFloat, CGFloat, CGFloat),
        dark: @escaping (AppAccentColor) -> (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            let accent = currentAccent
            let components = traits.userInterfaceStyle == .dark ? dark(accent) : light(accent)
            return UIColor(
                red: components.0 / 255,
                green: components.1 / 255,
                blue: components.2 / 255,
                alpha: 1
            )
        })
    }
}
