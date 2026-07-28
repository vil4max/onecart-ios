import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: WelcomeViewModel
    @State private var contentVisible = false

    init(model: AppModel) {
        _viewModel = StateObject(wrappedValue: WelcomeViewModel(session: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 12)

            Spacer(minLength: 24)

            middle
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible || reduceMotion ? 0 : 14)

            Spacer(minLength: 24)

            bottom
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneCartPalette.background.ignoresSafeArea())
        .onAppear {
            guard !contentVisible else { return }
            if reduceMotion {
                contentVisible = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.08)) {
                    contentVisible = true
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            OneCartMark()

            Text("welcome.title")
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("welcome.subtitle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible || reduceMotion ? 0 : 10)
    }

    @ViewBuilder
    private var middle: some View {
        switch model.welcomePhase {
        case .signIn:
            VStack(spacing: 16) {
                OnboardingStepRow(textKey: "onboarding.step.list", delay: 0.05)
                OnboardingStepRow(textKey: "onboarding.step.trolley", delay: 0.12)
                OnboardingStepRow(textKey: "onboarding.step.paid", delay: 0.19)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        case .connecting:
            connectingContent
        case let .failed(message):
            failedContent(message: message)
        }
    }

    private var bottom: some View {
        VStack(spacing: 12) {
            if model.welcomePhase == .signIn {
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

                Text("welcome.footer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, 8)
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
            if Self.isSignInDismissed(error) {
                viewModel.dismissWelcomeSignInAttempt()
                return
            }
            viewModel.reportWelcomeFailure(
                (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "welcome.sign_in_failed")
            )
        }
    }

    private static func isSignInDismissed(_ error: Error) -> Bool {
        guard let authError = error as? ASAuthorizationError else { return false }
        switch authError.code {
        case .canceled:
            return true
        case .unknown:
            return true
        default:
            return false
        }
    }
}

private struct OnboardingStepRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let textKey: LocalizedStringKey
    let delay: Double
    @State private var visible = false

    var body: some View {
        Text(textKey)
            .font(.title3)
            .foregroundStyle(.primary)
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .onAppear {
                guard !visible else { return }
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.88).delay(delay)) {
                        visible = true
                    }
                }
            }
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
