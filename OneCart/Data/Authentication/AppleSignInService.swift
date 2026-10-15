import AuthenticationServices
import Foundation
import OSLog
import Security
import UIKit

/// The app requests only the full name. Keychain payloads written by older builds also carry an
/// `email` key; decoding ignores it, and the next save drops it.
struct AppleSignInCredential: Codable, Equatable {
    let userID: String
    let givenName: String?
    let familyName: String?

    var providedDisplayName: String? {
        let parts = [givenName, familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    var displayName: String {
        providedDisplayName ?? String(localized: "common.default_user")
    }

    var accountID: UUID {
        OneCartStableID.uuid(for: "apple:\(userID)")
    }
}

enum AppleSignInCredentialState: Equatable {
    case authorized
    case revoked
    case notFound
    case unknown
}

enum AppleSignInError: LocalizedError {
    case missingIdentityToken
    case cancelled
    case failed

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            String(localized: "auth.apple_missing_credentials")
        case .cancelled:
            String(localized: "auth.apple_cancelled")
        case .failed:
            String(localized: "auth.apple_failed")
        }
    }
}

protocol AppleSignInCredentialStoring: AnyObject {
    func load() -> AppleSignInCredential?
    func save(_ credential: AppleSignInCredential)
    func clear()
}

/// The synchronous credential calls are main-actor requirements: the session and the
/// bootstrapper call them there, and the Keychain-backed service keeps its non-Sendable store
/// on the main actor. A nonisolated implementation still satisfies them.
protocol AppleSignInAuthenticating: AnyObject, Sendable {
    @MainActor func storedCredential() -> AppleSignInCredential?
    @MainActor func save(_ credential: AppleSignInCredential)
    @MainActor func clearCredential()
    func credentialState(for userID: String) async -> AppleSignInCredentialState
    @MainActor func makeCredential(from authorization: ASAuthorization) throws -> AppleSignInCredential
}

final class KeychainAppleSignInCredentialStore: AppleSignInCredentialStoring {
    private static let logger = Logger(subsystem: "com.vil555tim.onecart", category: "AppleSignIn")

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
            // Keep only the stable identifier in the App Group backup (no PII).
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
        // Backup stores only the stable userID; the name lives in the Keychain.
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

/// Main-actor isolated: the store is touched only by the session and the bootstrapper, which
/// run there.
@MainActor
final class AppleSignInService: AppleSignInAuthenticating {
    static let shared = AppleSignInService()

    private let store: any AppleSignInCredentialStoring

    init(store: any AppleSignInCredentialStoring = KeychainAppleSignInCredentialStore()) {
        self.store = store
    }

    func storedCredential() -> AppleSignInCredential? {
        store.load()
    }

    func save(_ credential: AppleSignInCredential) {
        store.save(credential)
    }

    func clearCredential() {
        store.clear()
    }

    nonisolated func credentialState(for userID: String) async -> AppleSignInCredentialState {
        #if targetEnvironment(simulator)
            return .authorized
        #else
            await withCheckedContinuation { continuation in
                ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                    continuation.resume(returning: Self.mapCredentialState(state))
                }
            }
        #endif
    }

    func makeCredential(from authorization: ASAuthorization) throws -> AppleSignInCredential {
        try credential(from: authorization)
    }

    private nonisolated static func mapCredentialState(
        _ state: ASAuthorizationAppleIDProvider.CredentialState
    ) -> AppleSignInCredentialState {
        switch state {
        case .authorized:
            return .authorized
        case .revoked:
            return .revoked
        case .notFound:
            return .notFound
        case .transferred:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private func credential(from authorization: ASAuthorization) throws -> AppleSignInCredential {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleSignInError.failed
        }
        guard appleIDCredential.identityToken != nil else {
            throw AppleSignInError.missingIdentityToken
        }

        let existing = store.load()
        let givenName = appleIDCredential.fullName?.givenName ?? existing?.givenName
        let familyName = appleIDCredential.fullName?.familyName ?? existing?.familyName

        return AppleSignInCredential(
            userID: appleIDCredential.user,
            givenName: givenName,
            familyName: familyName
        )
    }
}

@MainActor
enum AppleSignInPresentationAnchor {
    static var current: ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let preferredScenes = scenes.filter {
            $0.activationState == .foregroundActive
                || $0.activationState == .foregroundInactive
        }
        let orderedScenes = preferredScenes.isEmpty ? scenes : preferredScenes

        for scene in orderedScenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        for scene in orderedScenes {
            if let window = scene.windows.first(where: { !$0.isHidden }) {
                return window
            }
        }
        if let scene = orderedScenes.first ?? scenes.first {
            return UIWindow(windowScene: scene)
        }
        preconditionFailure("No UIWindowScene for Sign in with Apple presentation")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
