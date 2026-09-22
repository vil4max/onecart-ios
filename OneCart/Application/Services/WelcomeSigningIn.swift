import AuthenticationServices

/// The Welcome flow: Sign in with Apple completion, retry and failure reporting.
@MainActor
protocol WelcomeSigningIn: AnyObject {
    var welcomePhase: WelcomePhase { get }
    func completeAppleSignIn(authorization: ASAuthorization) async
    func completeAppleSignIn(credential: AppleSignInCredential) async
    func retryWelcome() async
    func reportWelcomeFailure(_ message: String)
    func dismissWelcomeSignInAttempt()
}
