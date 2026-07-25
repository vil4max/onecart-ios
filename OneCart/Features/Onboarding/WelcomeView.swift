import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
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
                Text("welcome.positioning")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(OneCartPalette.primary)
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
        case .audience:
            audienceContent
        case .connecting:
            connectingContent
        case let .failed(message):
            failedContent(message: message)
        }
    }

    private var signInContent: some View {
        AppleSignInAuthorizationButton(
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                handleSignInResult(result)
            }
        )
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }

    private var audienceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("welcome.audience.title")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            audienceButton(
                title: String(localized: "welcome.audience.just_me"),
                subtitle: String(localized: "welcome.audience.just_me.subtitle")
            ) {
                Task { await viewModel.completeHouseholdAudience(.justMe) }
            }
            audienceButton(
                title: String(localized: "welcome.audience.partner"),
                subtitle: String(localized: "welcome.audience.partner.subtitle")
            ) {
                Task { await viewModel.completeHouseholdAudience(.partner) }
            }
            audienceButton(
                title: String(localized: "welcome.audience.family"),
                subtitle: String(localized: "welcome.audience.family.subtitle")
            ) {
                Task { await viewModel.completeHouseholdAudience(.appleFamily) }
            }
        }
    }

    private func audienceButton(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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

struct CartMergeSheet: View {
    @EnvironmentObject private var model: AppModel
    let prompt: CartMergePrompt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(
                        String(
                            format: String(localized: "merge.prompt"),
                            prompt.privateFamilyName,
                            prompt.sharedFamilyName
                        )
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "merge.in_your_cart"), systemImage: "cart")
                        Text(summaryText(prompt.summary))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .oneCartCard()

                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await model.applyCartMergeChoice(.mergeIntoShared)
                                dismiss()
                            }
                        } label: {
                            Label(String(localized: "merge.action.merge"), systemImage: "arrow.right.arrow.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OneCartPrimaryButtonStyle())

                        Button {
                            Task {
                                await model.applyCartMergeChoice(.useSharedOnly)
                                dismiss()
                            }
                        } label: {
                            Label(String(localized: "merge.action.shared_only"), systemImage: "person.3.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OneCartSecondaryButtonStyle())

                        Button {
                            Task {
                                await model.applyCartMergeChoice(.keepPrivate)
                                dismiss()
                            }
                        } label: {
                            Text("merge.action.keep_private")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(OneCartPalette.background)
            .navigationTitle(String(localized: "merge.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
    }

    private func summaryText(_ summary: FamilySpaceContentSummary) -> String {
        var parts: [String] = []
        if summary.productCount > 0 {
            parts.append(
                String(format: String(localized: "merge.summary.products"), summary.productCount)
            )
        }
        if summary.storeCount > 0 {
            parts.append(
                String(format: String(localized: "merge.summary.stores"), summary.storeCount)
            )
        }
        if summary.historyCount > 0 {
            parts.append(
                String(format: String(localized: "merge.summary.history"), summary.historyCount)
            )
        }
        return parts.isEmpty ? String(localized: "merge.empty_starter") : parts.joined(separator: ", ")
    }
}

private struct AppleSignInAuthorizationButton: UIViewRepresentable {
    var onRequest: (ASAuthorizationAppleIDRequest) -> Void
    var onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRequest: onRequest, onCompletion: onCompletion)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: .black
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
