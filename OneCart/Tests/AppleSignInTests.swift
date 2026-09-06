import CloudKit
import CoreData
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

    func testKeychainStoreFallsBackToUserDefaultsBackup() throws {
        let service = "onecart.tests.\(UUID().uuidString)"
        let defaultsSuite = "onecart.tests.suite.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let store = KeychainAppleSignInCredentialStore(service: service, defaults: defaults)
        let credential = AppleSignInCredential(
            userID: "user.backup.test",
            email: "backup@example.com",
            givenName: "Backup",
            familyName: "User"
        )
        store.save(credential)

        // Clear only keychain items directly
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)

        // Store load should fall back to defaults backup
        let loaded = store.load()
        XCTAssertEqual(loaded, credential)

        // Clean up
        store.clear()
        XCTAssertNil(store.load())
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    func testSimulatorCredentialStateReturnsAuthorized() async {
        #if targetEnvironment(simulator)
            let service = AppleSignInService()
            let state = await service.credentialState(for: "any-user")
            XCTAssertEqual(state, .authorized)
        #endif
    }

    @MainActor
    func testWelcomeViewModelSignInWithTestAccountBootstrapsSession() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        let service = "onecart.tests.\(UUID().uuidString)"
        let defaultsSuite = "onecart.tests.suite.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let store = KeychainAppleSignInCredentialStore(service: service, defaults: defaults)
        let appleSignIn = AppleSignInService(store: store)
        let session = AppSession(
            persistence: persistence,
            defaults: defaults,
            appleSignIn: appleSignIn
        )
        let viewModel = WelcomeViewModel(session: session)
        await viewModel.signInWithTestAccount()

        XCTAssertFalse(session.needsWelcome)
        XCTAssertEqual(session.account?.displayName, "Max")
        let expectedCartName = try AppSession.householdCartName(for: XCTUnwrap(session.account))
        XCTAssertEqual(session.activeFamilySpace?.displayName, expectedCartName)
        XCTAssertEqual(store.load()?.givenName, "Max")

        // Clean up
        session.signOut()
        XCTAssertTrue(session.needsWelcome)
        XCTAssertNil(store.load())
        defaults.removePersistentDomain(forName: defaultsSuite)
    }
}
