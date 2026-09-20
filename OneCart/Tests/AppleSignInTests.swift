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

    func testKeychainAppleSignInCredentialStorePersistsCredential() throws {
        let store = try makeKeychainStore().store
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
        let (store, defaults, service) = try makeKeychainStore()
        let credential = AppleSignInCredential(
            userID: "user.backup.test",
            email: "backup@example.com",
            givenName: "Backup",
            familyName: "User"
        )
        store.save(credential)

        // The App Group backup must be PII-free: only the stable userID.
        XCTAssertEqual(defaults.string(forKey: store.backupKey), credential.userID)
        XCTAssertNil(defaults.data(forKey: store.backupKey))

        // Clear only keychain items directly
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)

        // Store load should fall back to the PII-free defaults backup (userID only)
        let loaded = store.load()
        XCTAssertEqual(loaded?.userID, credential.userID)
        XCTAssertNil(loaded?.email)
        XCTAssertNil(loaded?.givenName)
        XCTAssertNil(loaded?.familyName)

        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.string(forKey: store.backupKey))
    }

    func testCredentialStateForNeverIssuedUserID() async throws {
        let service = try AppleSignInService(store: makeKeychainStore().store)
        let state = await service.credentialState(for: "onecart.tests.\(UUID().uuidString)")
        #if targetEnvironment(simulator)
            // The simulator has no Apple ID provider, so the service short-circuits.
            XCTAssertEqual(state, .authorized)
        #else
            XCTAssertNotEqual(state, .authorized, "A user ID Apple never issued must not read as authorized")
        #endif
    }

    @MainActor
    func testWelcomeViewModelSignInWithTestAccountBootstrapsSession() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        let (store, defaults, _) = try makeKeychainStore()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults,
            appleSignIn: AppleSignInService(store: store)
        )
        let viewModel = WelcomeViewModel(session: session)
        await viewModel.signInWithTestAccount()

        XCTAssertFalse(session.needsWelcome)
        XCTAssertEqual(session.account?.displayName, "Alex")
        let expectedCartName = try AppSession.householdCartName(for: XCTUnwrap(session.account))
        XCTAssertEqual(session.activeFamilySpace?.displayName, expectedCartName)
        XCTAssertEqual(store.load()?.givenName, "Alex")

        session.signOut()
        XCTAssertTrue(session.needsWelcome)
        XCTAssertNil(store.load())
    }

    /// A unique Keychain service per test plus an isolated backup suite; teardown removes
    /// the items even when the test throws before its own `clear()`.
    private func makeKeychainStore() throws
        -> (store: KeychainAppleSignInCredentialStore, defaults: UserDefaults, service: String)
    {
        let service = "onecart.tests.\(UUID().uuidString)"
        let defaults = try makeDefaults()
        addTeardownBlock {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            SecItemDelete(query as CFDictionary)
        }
        return (KeychainAppleSignInCredentialStore(service: service, defaults: defaults), defaults, service)
    }
}
