import AuthenticationServices
import Foundation

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
