import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 64.0
    let viewModel: WelcomeViewModel
    @State private var contentVisible = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                content
                Spacer(minLength: 24)
            }

            ScrollView {
                content
                    .padding(.vertical, 24)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear(perform: reveal)
    }

    private var content: some View {
        VStack(spacing: 32) {
            brandHero

            switch viewModel.phase {
            case .signIn:
                features
                signInActions
            case .connecting:
                connecting
            case let .failed(message):
                failed(message: message)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible || reduceMotion ? 0 : 12)
    }

    private var brandHero: some View {
        VStack(spacing: 12) {
            Image("LaunchIcon")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .padding(10)
                .glassEffect(
                    .regular.tint(OneCartPalette.primary(for: colorScheme, accent: viewModel.accentColor)),
                    in: .rect(cornerRadius: iconSize * 0.34)
                )
                .accessibilityHidden(true)
                .padding(.bottom, 8)

            Text("common.app_name")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("welcome.app_name")

            Text("welcome.title")
                .font(.title.weight(.bold))
                .accessibilityIdentifier("welcome.title")

            Text("welcome.subtitle")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomeFeatureLabel(textKey: "onboarding.step.list", systemImage: "person.2", accent: viewModel.accentColor)
            WelcomeFeatureLabel(textKey: "onboarding.step.trolley", systemImage: "cart", accent: viewModel.accentColor)
            WelcomeFeatureLabel(
                textKey: "onboarding.step.paid",
                systemImage: "checkmark.circle",
                accent: viewModel.accentColor
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signInActions: some View {
        VStack(spacing: 12) {
            AppleSignInAuthorizationButton(
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    handleSignInResult(result)
                }
            )
            .id(colorScheme)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .accessibilityHint(Text("welcome.footer"))
            .accessibilityIdentifier("welcome.sign_in")

            #if DEBUG
                // Hidden in the demo UI so store screenshots show the Release welcome screen.
                if !DemoUIMode.isEnabled {
                    Button {
                        Task { await viewModel.signInWithTestAccount() }
                    } label: {
                        Label("welcome.debug_test_account", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(OneCartPalette.primaryAccent(for: colorScheme, accent: viewModel.accentColor))
                    .accessibilityIdentifier("welcome.test_account_button")
                }
            #endif

            Text("welcome.footer")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var connecting: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("welcome.connecting")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome.connecting")
    }

    private func failed(message: String) -> some View {
        ContentUnavailableView {
            Label("welcome.failed_title", systemImage: "exclamationmark.icloud")
        } description: {
            Text(message)
        } actions: {
            Button("welcome.try_again") {
                Task { await viewModel.retryWelcome() }
            }
            .buttonStyle(.borderedProminent)
            .tint(OneCartPalette.primary(for: colorScheme, accent: viewModel.accentColor))
            .accessibilityIdentifier("welcome.try_again")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func reveal() {
        guard !contentVisible else { return }
        if reduceMotion {
            contentVisible = true
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.08)) {
                contentVisible = true
            }
        }
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            Task { await viewModel.completeAppleSignIn(authorization: authorization) }
        case let .failure(error):
            if Self.isSignInDismissed(error) {
                viewModel.dismissWelcomeSignInAttempt()
                return
            }
            #if DEBUG && targetEnvironment(simulator)
                // A simulator without an Apple ID cannot finish Sign in with Apple;
                // debug builds fall back to the demo account. Never compiled into Release.
                Task { await viewModel.signInWithTestAccount() }
            #else
                viewModel.reportSignInFailure(error)
            #endif
        }
    }

    /// Only `.canceled` means the user closed the sheet. `.unknown` is a real
    /// failure and must surface the error with Retry.
    private static func isSignInDismissed(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}

private struct WelcomeFeatureLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let textKey: LocalizedStringKey
    let systemImage: String
    let accent: AppAccentColor

    var body: some View {
        Label {
            Text(textKey)
        } icon: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent(for: colorScheme, accent: accent))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome.feature")
    }
}

private struct AppleSignInAuthorizationButton: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    var onRequest: (ASAuthorizationAppleIDRequest) -> Void
    var onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRequest: onRequest, onCompletion: onCompletion)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let style: ASAuthorizationAppleIDButton.Style = colorScheme == .dark ? .white : .black
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: style
        )
        button.cornerRadius = 14
        button.accessibilityIdentifier = "welcome.sign_in"
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleTap),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.onRequest = onRequest
        context.coordinator.onCompletion = onCompletion
    }

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding
    {
        var onRequest: (ASAuthorizationAppleIDRequest) -> Void
        var onCompletion: (Result<ASAuthorization, Error>) -> Void
        private var activeController: ASAuthorizationController?

        init(
            onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
            onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void
        ) {
            self.onRequest = onRequest
            self.onCompletion = onCompletion
        }

        @objc func handleTap() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            onRequest(request)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            activeController = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(
            controller _: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            activeController = nil
            onCompletion(.success(authorization))
        }

        func authorizationController(
            controller _: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            activeController = nil
            onCompletion(.failure(error))
        }

        func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
            AppleSignInPresentationAnchor.current
        }
    }
}
