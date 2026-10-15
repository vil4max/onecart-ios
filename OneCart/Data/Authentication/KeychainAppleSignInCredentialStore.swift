import Foundation
import OSLog
import Security

final class KeychainAppleSignInCredentialStore: AppleSignInCredentialStoring {
    private static let logger = Logger(subsystem: OneCartLog.subsystem, category: "AppleSignIn")

    private let service: String
    private let account: String
    private let defaults: UserDefaults

    /// App Group backup key. Only the stable `userID` is stored here — never
    /// the name (PII stays in the Keychain).
    var backupKey: String {
        "onecart.apple-sign-in.backup.\(service).\(account)"
    }

    init(
        service: String = "com.vil555tim.onecart.apple-sign-in",
        account: String = "current-user",
        defaults: UserDefaults = OneCartAppGroup.defaults ?? .standard
    ) {
        self.service = service
        self.account = account
        self.defaults = defaults
    }

    func load() -> AppleSignInCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
            let credential = try? JSONDecoder().decode(AppleSignInCredential.self, from: data)
        {
            updateBackup(userID: credential.userID)
            return credential
        }

        // Fall back to the PII-free backup: recover the stable userID so the
        // account identity (and derived cart) survives a Keychain read failure.
        if let userID = defaults.string(forKey: backupKey) {
            let credential = AppleSignInCredential(
                userID: userID,
                givenName: nil,
                familyName: nil
            )
            if let data = try? JSONEncoder().encode(credential) {
                saveKeychain(data: data)
            }
            return credential
        }

        return nil
    }

    /// Encodes before touching the Keychain and replaces the item in place: Apple sends the
    /// name only on the first sign-in, so a failed write must not delete the stored one first.
    func save(_ credential: AppleSignInCredential) {
        guard let data = try? JSONEncoder().encode(credential) else { return }
        updateBackup(userID: credential.userID)
        saveKeychain(data: data)
    }

    func clear() {
        clearKeychain()
        defaults.removeObject(forKey: backupKey)
    }

    private func updateBackup(userID: String) {
        guard defaults.string(forKey: backupKey) != userID else { return }
        defaults.set(userID, forKey: backupKey)
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func saveKeychain(data: Data) {
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else {
            if updateStatus != errSecSuccess {
                Self.logger.error("keychain update fail status=\(updateStatus, privacy: .public)")
            }
            return
        }
        let addQuery = itemQuery.merging(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Self.logger.error("keychain add fail status=\(addStatus, privacy: .public)")
        }
    }

    private func clearKeychain() {
        let status = SecItemDelete(itemQuery as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            Self.logger.error("keychain delete fail status=\(status, privacy: .public)")
        }
    }
}
