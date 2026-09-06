@testable import OneCart
import XCTest

final class DevicePreferencesTests: XCTestCase {
    func testParticipantDisplayNamePersistsAndReloads() throws {
        let defaults = try makeDefaults()
        let preferences = DevicePreferences(defaults: defaults)
        preferences.participantDisplayName = "  Max  "
        XCTAssertEqual(preferences.participantDisplayName, "  Max  ")
        XCTAssertEqual(
            defaults.string(forKey: "onecart.participant-display-name"),
            "Max"
        )

        let reloaded = DevicePreferences(defaults: defaults)
        XCTAssertEqual(reloaded.participantDisplayName, "Max")

        defaults.set("Tim", forKey: "onecart.participant-display-name")
        reloaded.reloadFromDefaults()
        XCTAssertEqual(reloaded.participantDisplayName, "Tim")

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

    func testIPadSupportedOrientationsDeclaredInBundle() {
        let appBundle = Bundle(for: AppDelegate.self)
        let infoPlistURL = appBundle.bundleURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let orientations = plist["UISupportedInterfaceOrientations~ipad"] as? [String]
        else {
            XCTFail("UISupportedInterfaceOrientations~ipad must be declared in Info.plist at \(infoPlistURL.path)")
            return
        }
        XCTAssertTrue(orientations.contains("UIInterfaceOrientationPortrait"))
        XCTAssertTrue(orientations.contains("UIInterfaceOrientationPortraitUpsideDown"))
        XCTAssertTrue(orientations.contains("UIInterfaceOrientationLandscapeLeft"))
        XCTAssertTrue(orientations.contains("UIInterfaceOrientationLandscapeRight"))
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
}
