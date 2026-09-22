import AuthenticationServices
import Foundation
@testable import OneCart

@MainActor
@Observable
final class FakeWelcomeSignIn: WelcomeSigningIn {
    var welcomePhase: WelcomePhase = .signIn
    var completedAuthorizationCount = 0
    var completedCredentials: [AppleSignInCredential] = []
    var retryCount = 0
    var reportedFailures: [String] = []
    var dismissCount = 0

    func completeAppleSignIn(authorization _: ASAuthorization) async {
        completedAuthorizationCount += 1
    }

    func completeAppleSignIn(credential: AppleSignInCredential) async {
        completedCredentials.append(credential)
    }

    func retryWelcome() async {
        retryCount += 1
    }

    func reportWelcomeFailure(_ message: String) {
        reportedFailures.append(message)
        welcomePhase = .failed(message)
    }

    func dismissWelcomeSignInAttempt() {
        dismissCount += 1
        welcomePhase = .signIn
    }
}
