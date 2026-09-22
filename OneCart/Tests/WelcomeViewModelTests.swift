import Foundation
@testable import OneCart
import Testing

@MainActor
@Suite("WelcomeViewModelTests")
struct WelcomeViewModelTests {
    private struct DescribedError: LocalizedError {
        var errorDescription: String? {
            "iCloud is unavailable"
        }
    }

    private struct PlainError: Error {}

    private func makeViewModel() throws -> (WelcomeViewModel, FakeWelcomeSignIn, IsolatedPreferences) {
        let isolated = try IsolatedPreferences()
        let signIn = FakeWelcomeSignIn()
        let state = FakeSessionState(preferences: isolated.preferences)
        return (WelcomeViewModel(signIn: signIn, state: state), signIn, isolated)
    }

    @Test("REQ-AUTH-010: the phase mirrors the session and retry forwards")
    func phaseMirrorsSessionAndRetryForwards() async throws {
        let (viewModel, signIn, isolated) = try makeViewModel()
        #expect(viewModel.phase == .signIn)

        signIn.welcomePhase = .connecting
        #expect(viewModel.phase == .connecting)

        await viewModel.retryWelcome()
        #expect(signIn.retryCount == 1)

        isolated.preferences.accentColor = .emerald
        #expect(viewModel.accentColor == .emerald)
    }

    @Test("REQ-AUTH-010: a sign-in failure shows the provider's description or the generic message")
    func signInFailureUsesDescriptionOrGenericMessage() throws {
        let (viewModel, signIn, _) = try makeViewModel()

        viewModel.reportSignInFailure(DescribedError())
        viewModel.reportSignInFailure(PlainError())

        #expect(signIn.reportedFailures == [
            "iCloud is unavailable",
            String(localized: "welcome.sign_in_failed"),
        ])
        #expect(viewModel.phase == .failed(String(localized: "welcome.sign_in_failed")))
    }

    @Test("REQ-AUTH-010: dismissing the Apple sheet and explicit failures forward to the session")
    func dismissAndExplicitFailureForward() throws {
        let (viewModel, signIn, _) = try makeViewModel()

        viewModel.reportWelcomeFailure("Store failed")
        #expect(signIn.reportedFailures == ["Store failed"])
        #expect(viewModel.phase == .failed("Store failed"))

        viewModel.dismissWelcomeSignInAttempt()
        #expect(signIn.dismissCount == 1)
        #expect(viewModel.phase == .signIn)
    }

    #if DEBUG
        @Test("REQ-AUTH-010: the debug test account signs in as the demo owner")
        func accountSignsInAsDemoOwner() async throws {
            let (viewModel, signIn, _) = try makeViewModel()

            await viewModel.signInWithTestAccount()

            let credential = try #require(signIn.completedCredentials.first)
            #expect(credential.userID == "onecart-demo-owner")
            #expect(credential.givenName == "Alex")
            #expect(credential.email == nil)
            #expect(signIn.completedAuthorizationCount == 0)
        }
    #endif
}
