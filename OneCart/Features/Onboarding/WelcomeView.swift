import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: WelcomeViewModel

    init(model: AppModel) {
        _viewModel = StateObject(wrappedValue: WelcomeViewModel(session: model))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 14) {
                OneCartMark()
                Text("welcome.title")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("welcome.subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            content

            Text("welcome.footer")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneCartPalette.background)
    }

    @ViewBuilder
    private var content: some View {
        switch model.welcomePhase {
        case .signIn:
            signInContent
        case .connecting:
            connectingContent
        case let .failed(message):
            failedContent(message: message)
        }
    }

    private var signInContent: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingStepRow(systemImage: "list.bullet", textKey: "onboarding.step.list")
                OnboardingStepRow(systemImage: "cart.fill", textKey: "onboarding.step.trolley")
                OnboardingStepRow(systemImage: "checkmark.seal.fill", textKey: "onboarding.step.paid")
            }

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
            .frame(height: 50)
        }
    }

    private var connectingContent: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("welcome.connecting")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func failedContent(message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.footnote)
                .foregroundColor(OneCartPalette.danger)
                .multilineTextAlignment(.center)

            Button(String(localized: "welcome.try_again")) {
                Task { await viewModel.retryWelcome() }
            }
            .buttonStyle(OneCartPrimaryButtonStyle())
        }
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            Task { await viewModel.completeAppleSignIn(authorization: authorization) }
        case let .failure(error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            viewModel.reportWelcomeFailure(
                (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "welcome.sign_in_failed")
            )
        }
    }
}

private struct OnboardingStepRow: View {
    let systemImage: String
    let textKey: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
                .frame(width: 24)
            Text(textKey)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(
            controller _: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            onCompletion(.success(authorization))
        }

        func authorizationController(
            controller _: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            onCompletion(.failure(error))
        }

        func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
            AppleSignInPresentationAnchor.current
        }
    }
}
