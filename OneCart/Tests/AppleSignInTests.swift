import CloudKit
import CoreData
@testable import OneCart
import XCTest

final class AppleSignInTests: XCTestCase {
    func test_REQ_AUTH_040_appleSignInCredentialBuildsDisplayNameAndAccountID() {
        let credential = AppleSignInCredential(
            userID: "001234.abcd",
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
            givenName: nil,
            familyName: nil
        )
        XCTAssertNil(withoutName.providedDisplayName)
        XCTAssertEqual(withoutName.displayName, String(localized: "common.default_user"))
    }

    func test_REQ_AUTH_020_keychainAppleSignInCredentialStorePersistsCredential() throws {
        let store = try makeKeychainStore().store
        let credential = AppleSignInCredential(
            userID: "001234.abcd",
            givenName: "Test",
            familyName: nil
        )
        store.save(credential)
        XCTAssertEqual(store.load(), credential)
        store.clear()
        XCTAssertNil(store.load())
    }

    func test_REQ_AUTH_020_keychainStoreFallsBackToUserDefaultsBackup() throws {
        let (store, defaults, service) = try makeKeychainStore()
        let credential = AppleSignInCredential(
            userID: "user.backup.test",
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
        XCTAssertNil(loaded?.givenName)
        XCTAssertNil(loaded?.familyName)

        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.string(forKey: store.backupKey))
    }

    func test_REQ_AUTH_020_savingTwiceReplacesTheStoredCredential() throws {
        let (store, defaults, _) = try makeKeychainStore()
        store.save(AppleSignInCredential(userID: "user.replace", givenName: "Alex", familyName: nil))
        store.save(AppleSignInCredential(userID: "user.replace", givenName: "Sam", familyName: "Doe"))

        XCTAssertEqual(store.load()?.providedDisplayName, "Sam Doe")
        XCTAssertEqual(defaults.string(forKey: store.backupKey), "user.replace")
    }

    func test_REQ_AUTH_020_legacyCredentialWithEmailLoadsAndResavingDropsTheEmail() throws {
        let (store, _, service) = try makeKeychainStore()
        // The payload an older build wrote, when the app still requested the Apple ID email.
        let legacy = Data(
            #"{"userID":"user.legacy","email":"legacy@example.com","givenName":"Alex","familyName":"Doe"}"#.utf8
        )
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "current-user",
            kSecValueData as String: legacy,
        ]
        XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.userID, "user.legacy")
        XCTAssertEqual(loaded.providedDisplayName, "Alex Doe")

        store.save(loaded)

        let stored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: readKeychainData(service: service)) as? [String: Any]
        )
        XCTAssertNil(stored["email"], "the session keeps no Apple ID email")
        XCTAssertEqual(stored["userID"] as? String, "user.legacy")
        XCTAssertEqual(stored["givenName"] as? String, "Alex")
    }

    @MainActor
    func test_REQ_AUTH_020_credentialStateForNeverIssuedUserID() async throws {
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
    func test_REQ_AUTH_010_welcomeViewModelSignInWithTestAccountBootstrapsSession() async throws {
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

    private func readKeychainData(service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "current-user",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
        return try XCTUnwrap(item as? Data)
    }
}
