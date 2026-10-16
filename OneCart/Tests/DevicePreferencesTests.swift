@testable import OneCart
import SwiftUI
import XCTest

@MainActor
final class DevicePreferencesTests: XCTestCase {
    func testParticipantDisplayNamePersistsAndReloads() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
        preferences.participantDisplayName = "  Alex  "
        XCTAssertEqual(preferences.participantDisplayName, "  Alex  ")
        XCTAssertEqual(
            defaults.string(forKey: "onecart.participant-display-name"),
            "Alex"
        )

        let reloaded = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
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
    /// is dropped at launch and on reload.
    func testThemeFollowsTheDeviceAtLaunch() throws {
        let defaults = try makeDefaults()
        defaults.set("dark", forKey: "onecart.theme")
        defaults.set("Папа", forKey: "onecart.unrelated-test-key")
        let preferences = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
        XCTAssertNil(defaults.string(forKey: "onecart.theme"))
        XCTAssertEqual(defaults.string(forKey: "onecart.unrelated-test-key"), "Папа")

        defaults.set("light", forKey: "onecart.theme")
        preferences.reloadFromDefaults()
        XCTAssertNil(defaults.string(forKey: "onecart.theme"))
    }

    /// The accent reaches the App Group suite the widget reads only through the injected
    /// `appGroupDefaults`, and a retired theme is dropped there too.
    func test_REQ_WIDGET_010_accentIsWrittenToTheInjectedAppGroupSuite() throws {
        let defaults = try makeDefaults()
        let appGroup = try makeDefaults()
        appGroup.set("dark", forKey: "onecart.theme")
        let preferences = DevicePreferences(defaults: defaults, appGroupDefaults: appGroup)
        XCTAssertEqual(appGroup.string(forKey: OneCartAppGroup.accentColorKey), preferences.accentColor.rawValue)
        XCTAssertNil(appGroup.string(forKey: "onecart.theme"))

        let other = try XCTUnwrap(AppAccentColor.allCases.first { $0 != preferences.accentColor })
        preferences.accentColor = other
        XCTAssertEqual(appGroup.string(forKey: OneCartAppGroup.accentColorKey), other.rawValue)
    }

    /// REQ-SHELL-030: the language comes from the system (per-app language in iOS Settings); a
    /// language stored by an older version is dropped without touching `AppleLanguages`.
    func testLanguageFollowsTheSystemAndKeepsAppleLanguages() throws {
        let defaults = try makeDefaults()
        defaults.set("uk", forKey: "onecart.language")
        defaults.set(["uk"], forKey: "AppleLanguages")
        let preferences = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
        XCTAssertNil(defaults.string(forKey: "onecart.language"))
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["uk"])

        defaults.set("ru", forKey: "onecart.language")
        preferences.reloadFromDefaults()
        XCTAssertNil(defaults.string(forKey: "onecart.language"))
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["uk"])
    }

    func testInviteLinkErrorDescriptionsAreNonEmpty() {
        XCTAssertFalse(InviteLinkError.noCart.localizedDescription.isEmpty)
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
        let item = CartInviteActivityItem(link: dummyLink, thumbnail: ShareThumbnailRenderer(accent: .ocean))
        let dummyController = UIActivityViewController(activityItems: [], applicationActivities: nil)
        XCTAssertNotNil(item.activityViewControllerLinkMetadata(dummyController)?.imageProvider)
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
        let preferences = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
        XCTAssertEqual(preferences.appIcon, .classic)
        XCTAssertEqual(preferences.accentColor, .emerald)
        XCTAssertEqual(defaults.string(forKey: "onecart.accent-color"), "emerald")

        defaults.set("ocean", forKey: "onecart.app-icon")
        defaults.set("berry", forKey: "onecart.accent-color")
        let reloaded = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
        XCTAssertEqual(reloaded.accentColor, .ocean)
        XCTAssertEqual(defaults.string(forKey: "onecart.accent-color"), "ocean")

        defaults.set("midnight", forKey: "onecart.app-icon")
        defaults.set("coral", forKey: "onecart.accent-color")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.accentColor, .sunset)
        XCTAssertEqual(defaults.string(forKey: "onecart.accent-color"), "sunset")
    }

    func testEveryAppIconCarriesAnAccent() {
        XCTAssertEqual(AppIconOption.classic.accent, .emerald)
        XCTAssertEqual(AppIconOption.ocean.accent, .ocean)
        XCTAssertEqual(AppIconOption.sunset.accent, .sunset)
        XCTAssertEqual(AppIconOption.midnight.accent, .sunset)
    }

    func testAccentChangeCallback() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults, appGroupDefaults: nil)

        var notifiedAccent: AppAccentColor?
        preferences.onAccentChanged = { notifiedAccent = $0 }
        preferences.accentColor = .coral
        XCTAssertEqual(notifiedAccent, .coral)
    }

    /// REQ-SHELL-030: cleaning isolated defaults leaves the App Group copy to the real defaults.
    func test_REQ_SHELL_030_retiredThemeCleanupOnIsolatedDefaultsDoesNotTouchAppGroup() throws {
        let appGroup = try XCTUnwrap(OneCartAppGroup.defaults, "App Group defaults unavailable")
        let original = appGroup.object(forKey: "onecart.theme")
        defer { appGroup.set(original, forKey: "onecart.theme") }
        appGroup.set("dark", forKey: "onecart.theme")

        let preferences = DevicePreferences(defaults: try makeDefaults(), appGroupDefaults: nil)
        preferences.reloadFromDefaults()

        XCTAssertEqual(appGroup.string(forKey: "onecart.theme"), "dark")
    }

    func testAppAccentColorProperties() {
        func key(_ rgb: AccentRGB) -> String {
            "\(rgb.red)-\(rgb.green)-\(rgb.blue)"
        }
        let accents = AppAccentColor.allCases

        XCTAssertEqual(Set(accents.map(\.id)).count, accents.count)
        for accent in accents {
            XCTAssertFalse(accent.id.isEmpty)
        }
        for role in AccentRole.allCases {
            for dark in [false, true] {
                let colours = accents.map { $0.rgb(for: role, dark: dark) }
                for rgb in colours {
                    for channel in [rgb.red, rgb.green, rgb.blue] {
                        XCTAssertTrue((0...255).contains(channel), "\(role) dark=\(dark) channel \(channel)")
                    }
                }
                // A picked accent must be visible: no two accents may share a colour in any role.
                XCTAssertEqual(
                    Set(colours.map(key)).count, accents.count,
                    "\(role) dark=\(dark) colours must differ between accents"
                )
            }
        }
    }

    func testAppIconOptionPropertiesAndDefaults() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
        XCTAssertEqual(preferences.appIcon, .classic)

        preferences.appIcon = .midnight
        XCTAssertEqual(preferences.appIcon, .midnight)
        XCTAssertEqual(defaults.string(forKey: "onecart.app-icon"), "midnight")

        let reloaded = DevicePreferences(defaults: defaults, appGroupDefaults: nil)
        XCTAssertEqual(reloaded.appIcon, .midnight)

        defaults.set("ocean", forKey: "onecart.app-icon")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.appIcon, .ocean)

        for option in AppIconOption.allCases {
            XCTAssertFalse(option.id.isEmpty)
            XCTAssertFalse(option.title.isEmpty)
            XCTAssertFalse(option.previewImageName.isEmpty)
        }
        XCTAssertNil(AppIconOption.classic.iconName)
        XCTAssertEqual(AppIconOption.midnight.iconName, "AppIcon-Midnight")
        XCTAssertEqual(AppIconOption.ocean.iconName, "AppIcon-Ocean")
        XCTAssertEqual(AppIconOption.sunset.iconName, "AppIcon-Sunset")
    }
}
