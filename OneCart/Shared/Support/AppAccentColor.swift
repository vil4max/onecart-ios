import Foundation

public enum AppAccentColor: String, CaseIterable, Identifiable, Sendable {
    case emerald
    case ocean
    case sunset
    case berry
    case coral

    public var id: String {
        rawValue
    }

    /// A stored or transported raw value (App Group defaults, a widget snapshot, a trip state)
    /// may be missing or written by a newer build; both draw with the default accent.
    public init(storedRawValue: String?) {
        self = storedRawValue.flatMap(Self.init(rawValue:)) ?? .emerald
    }

    /// The 0-255 channels of `role` in the light or dark appearance.
    public func rgb(for role: AccentRole, dark: Bool) -> AccentRGB {
        let shade = Self.shades(of: self).shade(for: role)
        return dark ? shade.dark : shade.light
    }
}

/// Where an accent colour is used; every surface draws an accent through one of these.
public enum AccentRole: CaseIterable, Sendable {
    /// Filled surfaces that carry white content.
    case primary
    /// Text and glyphs drawn on the background or on `primarySoft`.
    case primaryAccent
    /// Tinted backing for chips and icon tiles.
    case primarySoft
}

/// One colour as 0-255 sRGB channels, so app, widget and UIKit code share the same numbers.
public struct AccentRGB: Equatable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat

    public init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

private struct AccentShade {
    let light: AccentRGB
    let dark: AccentRGB

    init(_ light: AccentRGB, _ dark: AccentRGB) {
        self.light = light
        self.dark = dark
    }
}

private struct AccentShades {
    let primary: AccentShade
    let primaryAccent: AccentShade
    let primarySoft: AccentShade

    func shade(for role: AccentRole) -> AccentShade {
        switch role {
        case .primary:
            primary
        case .primaryAccent:
            primaryAccent
        case .primarySoft:
            primarySoft
        }
    }
}

extension AppAccentColor {
    /// The single colour table: per accent, primary, primaryAccent and primarySoft as
    /// (light, dark).
    private static func shades(of accent: AppAccentColor) -> AccentShades {
        switch accent {
        case .emerald:
            AccentShades(
                primary: AccentShade(AccentRGB(52, 120, 91), AccentRGB(62, 147, 112)),
                primaryAccent: AccentShade(AccentRGB(40, 95, 71), AccentRGB(116, 199, 159)),
                primarySoft: AccentShade(AccentRGB(225, 239, 231), AccentRGB(30, 51, 41))
            )
        case .ocean:
            AccentShades(
                primary: AccentShade(AccentRGB(34, 110, 205), AccentRGB(55, 135, 235)),
                primaryAccent: AccentShade(AccentRGB(25, 85, 165), AccentRGB(110, 175, 255)),
                primarySoft: AccentShade(AccentRGB(225, 238, 252), AccentRGB(25, 42, 65))
            )
        case .sunset:
            AccentShades(
                primary: AccentShade(AccentRGB(220, 100, 35), AccentRGB(240, 120, 50)),
                primaryAccent: AccentShade(AccentRGB(175, 75, 25), AccentRGB(255, 155, 90)),
                primarySoft: AccentShade(AccentRGB(253, 238, 226), AccentRGB(60, 35, 20))
            )
        case .berry:
            AccentShades(
                primary: AccentShade(AccentRGB(140, 65, 170), AccentRGB(165, 90, 195)),
                primaryAccent: AccentShade(AccentRGB(110, 48, 135), AccentRGB(205, 135, 235)),
                primarySoft: AccentShade(AccentRGB(244, 232, 248), AccentRGB(48, 28, 58))
            )
        case .coral:
            AccentShades(
                primary: AccentShade(AccentRGB(225, 75, 85), AccentRGB(245, 95, 105)),
                primaryAccent: AccentShade(AccentRGB(180, 55, 65), AccentRGB(255, 140, 148)),
                primarySoft: AccentShade(AccentRGB(253, 232, 234), AccentRGB(58, 26, 28))
            )
        }
    }
}
