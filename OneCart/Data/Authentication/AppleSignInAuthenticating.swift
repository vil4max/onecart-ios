import AuthenticationServices

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
