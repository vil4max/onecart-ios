import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class AppleSignInTests: XCTestCase {
    func testAppleSignInCredentialBuildsDisplayNameAndAccountID() {
        let credential = AppleSignInCredential(
            userID: "001234.abcd",
            email: "user@example.com",
            givenName: "Иван",
            familyName: "Петров"
        )
        XCTAssertEqual(credential.providedDisplayName, "Иван Петров")
        XCTAssertEqual(credential.displayName, "Иван Петров")
        XCTAssertEqual(
            credential.accountID,
            OneCartStableID.uuid(for: "apple:001234.abcd")
        )

        let withoutName = AppleSignInCredential(
            userID: "001234.abcd",
            email: nil,
            givenName: nil,
            familyName: nil
        )
        XCTAssertNil(withoutName.providedDisplayName)
        XCTAssertEqual(withoutName.displayName, String(localized: "common.default_user"))
    }

    func testKeychainAppleSignInCredentialStorePersistsCredential() {
        let service = "onecart.tests.\(UUID().uuidString)"
        let store = KeychainAppleSignInCredentialStore(service: service)
        let credential = AppleSignInCredential(
            userID: "001234.abcd",
            email: nil,
            givenName: "Test",
            familyName: nil
        )
        store.save(credential)
        XCTAssertEqual(store.load(), credential)
        store.clear()
        XCTAssertNil(store.load())
    }
}
