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
    }

    func testInviteLinkErrorDescriptionsAreNonEmpty() {
        XCTAssertFalse(InviteLinkError.notOwner.localizedDescription.isEmpty)
        XCTAssertFalse(InviteLinkError.offline.localizedDescription.isEmpty)
    }
}
