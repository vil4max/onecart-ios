import AuthenticationServices
import Foundation
import Security
import UIKit

struct AppleSignInCredential: Codable, Equatable {
    let userID: String
    let email: String?
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

protocol AppleSignInAuthenticating: AnyObject {
    func storedCredential() -> AppleSignInCredential?
    func save(_ credential: AppleSignInCredential)
    func clearCredential()
    func credentialState(for userID: String) async -> AppleSignInCredentialState
    func signIn() async throws -> AppleSignInCredential
    func makeCredential(from authorization: ASAuthorization) throws -> AppleSignInCredential
}

final class KeychainAppleSignInCredentialStore: AppleSignInCredentialStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.vil555tim.onecart.apple-sign-in",
        account: String = "current-user"
    ) {
        self.service = service
        self.account = account
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
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AppleSignInCredential.self, from: data)
    }

    func save(_ credential: AppleSignInCredential) {
        clear()
        guard let data = try? JSONEncoder().encode(credential) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class AppleSignInService: NSObject, AppleSignInAuthenticating {
    static let shared = AppleSignInService()

    private let store: AppleSignInCredentialStoring
    private var continuation: CheckedContinuation<AppleSignInCredential, Error>?

    init(store: AppleSignInCredentialStoring = KeychainAppleSignInCredentialStore()) {
        self.store = store
        super.init()
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

    func credentialState(for userID: String) async -> AppleSignInCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: Self.mapCredentialState(state))
            }
        }
    }

    @MainActor
    func signIn() async throws -> AppleSignInCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func makeCredential(from authorization: ASAuthorization) throws -> AppleSignInCredential {
        try credential(from: authorization)
    }

    private static func mapCredentialState(
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

    private func finish(with result: Result<AppleSignInCredential, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case let .success(credential):
            continuation.resume(returning: credential)
        case let .failure(error):
            continuation.resume(throwing: error)
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
        let email = appleIDCredential.email ?? existing?.email

        return AppleSignInCredential(
            userID: appleIDCredential.user,
            email: email,
            givenName: givenName,
            familyName: familyName
        )
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        do {
            let credential = try credential(from: authorization)
            store.save(credential)
            finish(with: .success(credential))
        } catch {
            finish(with: .failure(error))
        }
    }

    func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            finish(with: .failure(AppleSignInError.cancelled))
            return
        }
        finish(with: .failure(error))
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        AppleSignInPresentationAnchor.current
    }
}

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
            if let window = scene.windows.first(where: \.isKeyWindow) {
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
