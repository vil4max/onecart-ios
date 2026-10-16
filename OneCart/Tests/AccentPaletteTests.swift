@testable import OneCart
import SwiftUI
import Synchronization
import Testing
import UIKit

/// The one accent table and the palette over it, and how the widget and the trip resolve the
/// accent they draw with.
@Suite("Accent palette")
struct AccentPaletteTests {
    private struct Entry {
        let accent: AppAccentColor
        let role: AccentRole
        let light: AccentRGB
        let dark: AccentRGB

        init(_ accent: AppAccentColor, _ role: AccentRole, _ light: AccentRGB, _ dark: AccentRGB) {
            self.accent = accent
            self.role = role
            self.light = light
            self.dark = dark
        }
    }

    /// The values the three per-role tables (`primaryRGB`, `primaryAccentRGB`, `primarySoftRGB`)
    /// held before they became one table; a change here is a visible colour change.
    private static let previousTable: [Entry] = [
        Entry(.emerald, .primary, AccentRGB(52, 120, 91), AccentRGB(62, 147, 112)),
        Entry(.ocean, .primary, AccentRGB(34, 110, 205), AccentRGB(55, 135, 235)),
        Entry(.sunset, .primary, AccentRGB(220, 100, 35), AccentRGB(240, 120, 50)),
        Entry(.berry, .primary, AccentRGB(140, 65, 170), AccentRGB(165, 90, 195)),
        Entry(.coral, .primary, AccentRGB(225, 75, 85), AccentRGB(245, 95, 105)),
        Entry(.emerald, .primaryAccent, AccentRGB(40, 95, 71), AccentRGB(116, 199, 159)),
        Entry(.ocean, .primaryAccent, AccentRGB(25, 85, 165), AccentRGB(110, 175, 255)),
        Entry(.sunset, .primaryAccent, AccentRGB(175, 75, 25), AccentRGB(255, 155, 90)),
        Entry(.berry, .primaryAccent, AccentRGB(110, 48, 135), AccentRGB(205, 135, 235)),
        Entry(.coral, .primaryAccent, AccentRGB(180, 55, 65), AccentRGB(255, 140, 148)),
        Entry(.emerald, .primarySoft, AccentRGB(225, 239, 231), AccentRGB(30, 51, 41)),
        Entry(.ocean, .primarySoft, AccentRGB(225, 238, 252), AccentRGB(25, 42, 65)),
        Entry(.sunset, .primarySoft, AccentRGB(253, 238, 226), AccentRGB(60, 35, 20)),
        Entry(.berry, .primarySoft, AccentRGB(244, 232, 248), AccentRGB(48, 28, 58)),
        Entry(.coral, .primarySoft, AccentRGB(253, 232, 234), AccentRGB(58, 26, 28)),
    ]

    /// The colour drawn in the given appearance, as 0-255 channels.
    private func channels(of color: Color, dark: Bool) -> AccentRGB {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return AccentRGB((red * 255).rounded(), (green * 255).rounded(), (blue * 255).rounded())
    }

    @Test("REQ-SHELL-030: every role, scheme and accent keeps the colour it had before the table merge")
    func tableKeepsThePreviousColours() {
        #expect(Self.previousTable.count == AppAccentColor.allCases.count * AccentRole.allCases.count)
        for entry in Self.previousTable {
            #expect(entry.accent.rgb(for: entry.role, dark: false) == entry.light, "\(entry.accent) \(entry.role)")
            #expect(entry.accent.rgb(for: entry.role, dark: true) == entry.dark, "\(entry.accent) \(entry.role)")
        }
    }

    @Test("REQ-SHELL-030: a pinned scheme draws that scheme's colour; no scheme follows the appearance")
    func paletteDrawsTheTableColours() {
        for entry in Self.previousTable {
            let light = OneCartPalette.color(for: entry.role, scheme: .light, accent: entry.accent)
            let dark = OneCartPalette.color(for: entry.role, scheme: .dark, accent: entry.accent)
            let adaptive = OneCartPalette.color(for: entry.role, accent: entry.accent)
            #expect(channels(of: light, dark: true) == entry.light, "\(entry.accent) \(entry.role)")
            #expect(channels(of: dark, dark: false) == entry.dark, "\(entry.accent) \(entry.role)")
            #expect(channels(of: adaptive, dark: false) == entry.light, "\(entry.accent) \(entry.role)")
            #expect(channels(of: adaptive, dark: true) == entry.dark, "\(entry.accent) \(entry.role)")
        }
    }

    @Test("REQ-SHELL-030: a missing or unknown stored accent draws emerald")
    func storedRawValueFallsBackToEmerald() {
        #expect(AppAccentColor(storedRawValue: nil) == .emerald)
        #expect(AppAccentColor(storedRawValue: "midnight") == .emerald)
        for accent in AppAccentColor.allCases {
            #expect(AppAccentColor(storedRawValue: accent.rawValue) == accent)
        }
    }

    @Test("REQ-WIDGET-010: the widget and the shopping trip resolve the same accent from one snapshot")
    func widgetAndTripResolveTheSnapshotAccent() {
        let raws: [String?] = [nil, "unknown"] + AppAccentColor.allCases.map(\.rawValue)
        for raw in raws {
            let snapshot = WidgetCartSnapshot(
                cartTitle: "Weekend",
                totalCount: 0,
                purchasedCount: 0,
                isSyncing: false,
                lastUpdated: Date(timeIntervalSince1970: 0),
                familyMemberCount: 1,
                accentColorRaw: raw,
                items: []
            )
            let trip = ShoppingTripAttributes.ContentState(snapshot: snapshot)
            #expect(snapshot.accentColor == AppAccentColor(storedRawValue: raw))
            #expect(trip.accentColor == snapshot.accentColor)
        }
    }

    @Test("REQ-SHARE-070: the share thumbnail is drawn in the accent current when it draws")
    func shareThumbnailFollowsTheGivenAccent() throws {
        let picked = Mutex(AppAccentColor.emerald)
        let renderer = ShareThumbnailRenderer(currentAccent: { picked.withLock { $0 } })
        let first = try #require(renderer.thumbnailPNGData())
        picked.withLock { $0 = .ocean }
        // A theme picked after the renderer was built reaches the next thumbnail.
        #expect(try #require(renderer.thumbnailPNGData()) != first)
        let emerald = try #require(ShareThumbnailRenderer(accent: .emerald).thumbnailPNGData())
        let ocean = try #require(ShareThumbnailRenderer(accent: .ocean).thumbnailPNGData())
        #expect(!emerald.isEmpty)
        #expect(emerald != ocean)
    }
}
