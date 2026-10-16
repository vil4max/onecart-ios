import SwiftUI
import UIKit

extension EnvironmentValues {
    /// The accent views draw with. The app sets it at its root from `DevicePreferences`, so a
    /// change re-renders every reader; the widget and the Live Activity set it from their
    /// snapshot. The default only shows in previews and hosted views that set none.
    @Entry var accent: AppAccentColor = .emerald
}

public enum OneCartPalette {
    /// The accent colour of `role`. With a scheme it is that appearance's fixed colour (widgets
    /// pin their scheme); without one it follows the trait collection it is drawn in.
    public static func color(for role: AccentRole, scheme: ColorScheme? = nil, accent: AppAccentColor) -> Color {
        guard let scheme else {
            return adaptive(light: accent.rgb(for: role, dark: false), dark: accent.rgb(for: role, dark: true))
        }
        let rgb = accent.rgb(for: role, dark: scheme == .dark)
        return Color(red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255)
    }

    public static let background = Color(.systemGroupedBackground)
    public static let danger = adaptive(light: AccentRGB(185, 74, 72), dark: AccentRGB(232, 117, 111))

    public static func widgetBackground(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
        } else {
            Color.white
        }
    }

    private static func adaptive(light: AccentRGB, dark: AccentRGB) -> Color {
        Color(
            UIColor { traits in
                let rgb = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255, alpha: 1)
            })
    }
}
