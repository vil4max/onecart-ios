import AuthenticationServices
import Combine

/// Everything Welcome needs from the session; the composition root satisfies `init(session:)` with one object.
typealias WelcomeSessionServices = SessionStateReading & WelcomeSigningIn

/// Sign in with Apple, retry and failure reporting for the Welcome screen (REQ-AUTH-010).
@MainActor
@Observable
final class WelcomeViewModel {
    private let signIn: any WelcomeSigningIn
    private let state: any SessionStateReading

    init(signIn: any WelcomeSigningIn, state: any SessionStateReading) {
        self.signIn = signIn
        self.state = state
    }

    convenience init(session: any WelcomeSessionServices) {
        self.init(signIn: session, state: session)
    }

    var phase: WelcomePhase {
        signIn.welcomePhase
    }

    var accentColor: AppAccentColor {
        state.preferences.accentColor
    }

    func completeAppleSignIn(authorization: ASAuthorization) async {
        await signIn.completeAppleSignIn(authorization: authorization)
    }

    func retryWelcome() async {
        await signIn.retryWelcome()
    }

    func reportWelcomeFailure(_ message: String) {
        signIn.reportWelcomeFailure(message)
    }

    /// Shows the provider's own description when it has one; otherwise the generic sign-in failure.
    func reportSignInFailure(_ error: Error) {
        signIn.reportWelcomeFailure(
            (error as? LocalizedError)?.errorDescription
                ?? String(localized: "welcome.sign_in_failed")
        )
    }

    func dismissWelcomeSignInAttempt() {
        signIn.dismissWelcomeSignInAttempt()
    }

    #if DEBUG
        func signInWithTestAccount() async {
            let credential = AppleSignInCredential(
                userID: "onecart-demo-owner",
                email: nil,
                givenName: "Alex",
                familyName: nil
            )
            await signIn.completeAppleSignIn(credential: credential)
        }
    #endif
}

/// Bridges the current `@StateObject` screens until S3 wires them through `@State`.
extension WelcomeViewModel: ObservableObject {}
