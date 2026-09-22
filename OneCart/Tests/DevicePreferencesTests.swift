@testable import OneCart
import SwiftUI
import XCTest

@MainActor
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

    /// REQ-SHELL-030: the app follows the device appearance; a theme stored by an older version
    /// is dropped at launch, and the widget's copy is reset with it.
    func testThemeFollowsTheDeviceAtLaunch() throws {
        let defaults = try makeDefaults()
        defaults.set("dark", forKey: "onecart.theme")
        let preferences = DevicePreferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .system)
        XCTAssertNil(preferences.theme.colorScheme)

        defaults.set("light", forKey: "onecart.theme")
        preferences.reloadFromDefaults()
        XCTAssertEqual(preferences.theme, .system)
    }

    /// REQ-SHELL-030: the language comes from the system (per-app language in iOS Settings); a
    /// language stored by an older version is dropped without touching `AppleLanguages`.
    func testLanguageFollowsTheSystemAndKeepsAppleLanguages() throws {
        let defaults = try makeDefaults()
        defaults.set("uk", forKey: "onecart.language")
        defaults.set(["uk"], forKey: "AppleLanguages")
        let preferences = DevicePreferences(defaults: defaults)
        XCTAssertEqual(preferences.language, .system)
        XCTAssertNil(defaults.string(forKey: "onecart.language"))
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["uk"])

        defaults.set("ru", forKey: "onecart.language")
        preferences.reloadFromDefaults()
        XCTAssertEqual(preferences.language, .system)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["uk"])
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

    /// REQ-SHELL-030: the accent follows the app icon; an accent stored by an older version
    /// (including berry and coral, which no icon carries) gives way to the icon's accent.
    func testAccentFollowsTheAppIconAtLaunch() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)
        XCTAssertEqual(preferences.appIcon, .classic)
        XCTAssertEqual(preferences.accentColor, .emerald)
        XCTAssertEqual(OneCartPalette.currentAccent, .emerald)

        defaults.set("ocean", forKey: "onecart.app-icon")
        defaults.set("berry", forKey: "onecart.accent-color")
        let reloaded = DevicePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.accentColor, .ocean)
        XCTAssertEqual(defaults.string(forKey: "onecart.accent-color"), "ocean")
        XCTAssertEqual(OneCartPalette.currentAccent, .ocean)

        defaults.set("midnight", forKey: "onecart.app-icon")
        defaults.set("coral", forKey: "onecart.accent-color")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.accentColor, .sunset)
        XCTAssertEqual(OneCartPalette.currentAccent, .sunset)
    }

    func testEveryAppIconCarriesAnAccent() {
        XCTAssertEqual(AppIconOption.classic.accent, .emerald)
        XCTAssertEqual(AppIconOption.ocean.accent, .ocean)
        XCTAssertEqual(AppIconOption.sunset.accent, .sunset)
        XCTAssertEqual(AppIconOption.midnight.accent, .sunset)
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
