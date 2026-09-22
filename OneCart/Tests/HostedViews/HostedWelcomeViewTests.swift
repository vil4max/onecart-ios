import AuthenticationServices
import Foundation
@testable import OneCart
import SwiftUI
import Testing

/// Welcome hosted over `FakeWelcomeSignIn`: the brand hero, Sign in with Apple, and the
/// connecting and failed phases with Retry (REQ-AUTH-010, REQ-SHELL-060).
@MainActor
@Suite("HostedWelcomeViewTests")
struct HostedWelcomeViewTests {
    @MainActor
    private struct Harness {
        let isolated: IsolatedPreferences
        let signIn = FakeWelcomeSignIn()
        let state: FakeSessionState
        let viewModel: WelcomeViewModel

        init() throws {
            isolated = try IsolatedPreferences()
            state = FakeSessionState(preferences: isolated.preferences)
            viewModel = WelcomeViewModel(signIn: signIn, state: state)
        }
    }

    @Test("REQ-SHELL-060: Welcome greets with OneCart Family, the pitch and Sign in with Apple")
    func signInPhaseShowsBrandAndAppleButton() async throws {
        let harness = try Harness()
        let hosted = HostedView(WelcomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        #expect(await hosted.pump { hosted.element(identifier: "welcome.app_name") != nil })

        #expect(hosted.element(identifier: "welcome.app_name")?.label == "OneCart Family")
        #expect(hosted.element(identifier: "welcome.title")?.label == String(localized: "welcome.title"))
        #expect(hosted.containsLabel(String(localized: "welcome.subtitle")))
        #expect(hosted.elements(identifier: "welcome.feature").count == 3)
        #expect(hosted.containsLabel(String(localized: "welcome.footer")))

        let appleButtons = hosted.views(of: ASAuthorizationAppleIDButton.self)
        #expect(appleButtons.count == 1)
        #expect(appleButtons.first?.accessibilityIdentifier == "welcome.sign_in")
        #expect(hosted.element(identifier: "welcome.try_again") == nil)
        #expect(hosted.element(identifier: "welcome.connecting") == nil)
    }

    #if DEBUG
        @Test("REQ-AUTH-010: the debug test account button signs in through the session")
        func accountButtonSignsIn() async throws {
            let harness = try Harness()
            let hosted = HostedView(WelcomeView(viewModel: harness.viewModel))
            defer { hosted.tearDown() }
            #expect(await hosted.pump { hosted.element(identifier: "welcome.test_account_button") != nil })

            let button = try #require(hosted.element(identifier: "welcome.test_account_button"))
            #expect(button.activate())
            #expect(await hosted.pump { harness.signIn.completedCredentials.count == 1 })
            #expect(harness.signIn.completedCredentials.first?.userID == "onecart-demo-owner")
        }
    #endif

    @Test("REQ-AUTH-010: Welcome follows the session phase: connecting, failed with Retry, back to sign-in")
    func phasesReRender() async throws {
        let harness = try Harness()
        let hosted = HostedView(WelcomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        #expect(await hosted.pump { hosted.element(identifier: "welcome.app_name") != nil })

        harness.signIn.welcomePhase = .connecting
        #expect(await hosted.pump { hosted.element(identifier: "welcome.connecting") != nil })
        #expect(hosted.element(identifier: "welcome.connecting")?.label?
            .contains(String(localized: "welcome.connecting")) == true)
        #expect(hosted.views(of: ASAuthorizationAppleIDButton.self).isEmpty)

        harness.signIn.welcomePhase = .failed("iCloud is unavailable")
        #expect(await hosted.pump { hosted.element(identifier: "welcome.try_again") != nil })
        #expect(hosted.containsLabel(String(localized: "welcome.failed_title")))
        #expect(hosted.containsLabel("iCloud is unavailable"))
        let retry = try #require(hosted.element(identifier: "welcome.try_again"))
        #expect(retry.label == String(localized: "welcome.try_again"))
        #expect(retry.activate())
        #expect(await hosted.pump { harness.signIn.retryCount == 1 })

        harness.signIn.welcomePhase = .signIn
        #expect(await hosted.pump { hosted.views(of: ASAuthorizationAppleIDButton.self).count == 1 })
        #expect(hosted.element(identifier: "welcome.try_again") == nil)
    }
}
