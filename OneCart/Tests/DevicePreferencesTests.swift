@testable import OneCart
import SwiftUI
import XCTest

final class DevicePreferencesTests: XCTestCase {
    func testParticipantDisplayNamePersistsAndReloads() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)
        preferences.participantDisplayName = "  Alex  "
        XCTAssertEqual(preferences.participantDisplayName, "  Alex  ")
        XCTAssertEqual(
            defaults.string(forKey: "onecart.participant-display-name"),
            "Alex"
        )

        let reloaded = DevicePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.participantDisplayName, "Alex")

        defaults.set("Sam", forKey: "onecart.participant-display-name")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.participantDisplayName, "Sam")

        defaults.set("User", forKey: "onecart.participant-display-name")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.participantDisplayName, "")
        XCTAssertTrue(ParticipantDisplayName.isPlaceholder("User"))
        XCTAssertTrue(ParticipantDisplayName.isPlaceholder("Family member"))
        XCTAssertFalse(ParticipantDisplayName.isPlaceholder("Папа"))
    }

    func testThemeDefaultsToSystemAndPersists() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .system)

        preferences.theme = .dark
        XCTAssertEqual(preferences.theme, .dark)
        XCTAssertEqual(defaults.string(forKey: "onecart.theme"), "dark")

        let reloaded = DevicePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.theme, .dark)

        defaults.set("light", forKey: "onecart.theme")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.theme, .light)

        defaults.set("invalid-theme", forKey: "onecart.theme")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.theme, .system)
    }

    func testLanguageDefaultsToSystemAndPersists() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)
        XCTAssertEqual(preferences.language, .system)
        XCTAssertNil(preferences.language.languageCode)

        preferences.language = .english
        XCTAssertEqual(preferences.language, .english)
        XCTAssertEqual(defaults.string(forKey: "onecart.language"), "en")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        XCTAssertEqual(preferences.effectiveLocale.identifier, "en")

        preferences.language = .ukrainian
        XCTAssertEqual(preferences.language, .ukrainian)
        XCTAssertEqual(defaults.string(forKey: "onecart.language"), "uk")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["uk"])
        XCTAssertEqual(preferences.effectiveLocale.identifier, "uk")

        preferences.language = .russian
        XCTAssertEqual(preferences.language, .russian)
        XCTAssertEqual(defaults.string(forKey: "onecart.language"), "ru")
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["ru"])
        XCTAssertEqual(preferences.effectiveLocale.identifier, "ru")

        preferences.language = .system
        XCTAssertEqual(preferences.language, .system)
        XCTAssertEqual(defaults.string(forKey: "onecart.language"), "system")
        XCTAssertNotEqual(defaults.stringArray(forKey: "AppleLanguages"), ["ru"])

        let reloaded = DevicePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.language, .system)

        defaults.set("uk", forKey: "onecart.language")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.language, .ukrainian)

        defaults.set("unknown-code", forKey: "onecart.language")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.language, .system)
    }

    func testAppLanguagePropertiesAndLocales() {
        XCTAssertEqual(AppLanguage.system.id, "system")
        XCTAssertEqual(AppLanguage.english.id, "en")
        XCTAssertEqual(AppLanguage.ukrainian.id, "uk")
        XCTAssertEqual(AppLanguage.russian.id, "ru")

        XCTAssertNil(AppLanguage.system.locale)
        XCTAssertEqual(AppLanguage.english.locale?.identifier, "en")
        XCTAssertEqual(AppLanguage.ukrainian.locale?.identifier, "uk")
        XCTAssertEqual(AppLanguage.russian.locale?.identifier, "ru")

        XCTAssertFalse(AppLanguage.system.title.isEmpty)
        XCTAssertFalse(AppLanguage.english.title.isEmpty)
        XCTAssertFalse(AppLanguage.ukrainian.title.isEmpty)
        XCTAssertFalse(AppLanguage.russian.title.isEmpty)
    }

    func testAppThemePropertiesAndColorScheme() {
        XCTAssertEqual(AppTheme.system.id, "system")
        XCTAssertEqual(AppTheme.light.id, "light")
        XCTAssertEqual(AppTheme.dark.id, "dark")

        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)

        XCTAssertFalse(AppTheme.system.title.isEmpty)
        XCTAssertFalse(AppTheme.light.title.isEmpty)
        XCTAssertFalse(AppTheme.dark.title.isEmpty)
    }

    func testInviteLinkErrorDescriptionsAreNonEmpty() {
        XCTAssertFalse(InviteLinkError.notOwner.localizedDescription.isEmpty)
        XCTAssertFalse(InviteLinkError.offline.localizedDescription.isEmpty)
    }

    func testIPhoneSupportedOrientationsDeclaredInBundle() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let infoPlistURL = appBundle.bundleURL.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        // iPhone only (TARGETED_DEVICE_FAMILY = 1): the app is laid out for portrait.
        XCTAssertEqual(
            plist["UISupportedInterfaceOrientations"] as? [String],
            ["UIInterfaceOrientationPortrait"]
        )
    }

    func testCartInviteActivityItemProperties() throws {
        let dummyLink = try FamilyInviteLink(
            id: UUID(),
            familyName: "Test Family",
            url: XCTUnwrap(URL(string: "https://example.com/invite"))
        )
        let item = CartInviteActivityItem(link: dummyLink)
        let dummyController = UIActivityViewController(activityItems: [], applicationActivities: nil)
        XCTAssertEqual(item.activityViewControllerPlaceholderItem(dummyController) as? URL, dummyLink.url)
        XCTAssertEqual(
            item.activityViewController(
                dummyController,
                itemForActivityType: UIActivity.ActivityType.message
            ) as? String,
            dummyLink.shareMessage
        )
        XCTAssertEqual(
            item.activityViewController(dummyController, itemForActivityType: UIActivity.ActivityType.airDrop) as? URL,
            dummyLink.url
        )
        let subject = item.activityViewController(
            dummyController,
            subjectForActivityType: UIActivity.ActivityType?.none
        )
        XCTAssertEqual(subject, dummyLink.shareTitle)
    }

    func testAccentColorDefaultsToEmeraldAndPersists() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)
        XCTAssertEqual(preferences.accentColor, .emerald)
        XCTAssertEqual(OneCartPalette.currentAccent, .emerald)

        preferences.accentColor = .ocean
        XCTAssertEqual(preferences.accentColor, .ocean)
        XCTAssertEqual(defaults.string(forKey: "onecart.accent-color"), "ocean")
        XCTAssertEqual(OneCartPalette.currentAccent, .ocean)

        let reloaded = DevicePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.accentColor, .ocean)

        defaults.set("sunset", forKey: "onecart.accent-color")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.accentColor, .sunset)
        XCTAssertEqual(OneCartPalette.currentAccent, .sunset)

        defaults.set("invalid-accent", forKey: "onecart.accent-color")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.accentColor, .emerald)
        XCTAssertEqual(OneCartPalette.currentAccent, .emerald)
    }

    func testAccentAndThemeChangeCallbacks() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)

        var notifiedAccent: AppAccentColor?
        preferences.onAccentChanged = { notifiedAccent = $0 }
        preferences.accentColor = .coral
        XCTAssertEqual(notifiedAccent, .coral)

        var notifiedTheme: AppTheme?
        preferences.onThemeChanged = { notifiedTheme = $0 }
        preferences.theme = .dark
        XCTAssertEqual(notifiedTheme, .dark)
    }

    func testAppAccentColorProperties() {
        typealias Palette = (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat))
        func key(_ rgb: (CGFloat, CGFloat, CGFloat)) -> String {
            "\(rgb.0)-\(rgb.1)-\(rgb.2)"
        }
        let tables: [(name: String, value: (AppAccentColor) -> Palette)] = [
            ("primary", { $0.primaryRGB }),
            ("primaryStrong", { $0.primaryStrongRGB }),
            ("primaryAccent", { $0.primaryAccentRGB }),
            ("primarySoft", { $0.primarySoftRGB }),
        ]
        let accents = AppAccentColor.allCases

        XCTAssertEqual(Set(accents.map(\.id)).count, accents.count)
        for accent in accents {
            XCTAssertFalse(accent.id.isEmpty)
            XCTAssertFalse(accent.title.isEmpty)
            let primary = accent.primaryRGB.light
            XCTAssertEqual(
                accent.swatchColor,
                Color(red: primary.0 / 255, green: primary.1 / 255, blue: primary.2 / 255)
            )
        }
        for table in tables {
            for accent in accents {
                let palette = table.value(accent)
                for channel in [
                    palette.light.0, palette.light.1, palette.light.2,
                    palette.dark.0, palette.dark.1, palette.dark.2,
                ] {
                    XCTAssertTrue((0 ... 255).contains(channel), "\(accent.id) \(table.name) channel \(channel)")
                }
            }
            // A picked accent must be visible: no two accents may share a colour in any role.
            XCTAssertEqual(
                Set(accents.map { key(table.value($0).light) }).count, accents.count,
                "\(table.name) light colours must differ between accents"
            )
            XCTAssertEqual(
                Set(accents.map { key(table.value($0).dark) }).count, accents.count,
                "\(table.name) dark colours must differ between accents"
            )
        }
    }

    func testAppIconOptionPropertiesAndDefaults() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)
        XCTAssertEqual(preferences.appIcon, .classic)

        preferences.appIcon = .midnight
        XCTAssertEqual(preferences.appIcon, .midnight)
        XCTAssertEqual(defaults.string(forKey: "onecart.app-icon"), "midnight")

        let reloaded = DevicePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.appIcon, .midnight)

        defaults.set("ocean", forKey: "onecart.app-icon")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.appIcon, .ocean)

        for option in AppIconOption.allCases {
            XCTAssertFalse(option.id.isEmpty)
            XCTAssertFalse(option.title.isEmpty)
            XCTAssertFalse(option.previewSymbol.isEmpty)
            XCTAssertFalse(option.previewImageName.isEmpty)
        }
        XCTAssertNil(AppIconOption.classic.iconName)
        XCTAssertEqual(AppIconOption.midnight.iconName, "AppIcon-Midnight")
        XCTAssertEqual(AppIconOption.ocean.iconName, "AppIcon-Ocean")
        XCTAssertEqual(AppIconOption.sunset.iconName, "AppIcon-Sunset")
    }
}
