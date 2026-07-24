import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 14) {
                OneCartMark()
                Text("Семейная корзина")
                    .font(.largeTitle.bold())
                Text("Войдите с Apple ID — списки подтянутся из iCloud автоматически.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            content

            Text("Нужен Apple ID и включённый iCloud на устройстве.")
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
        case .failed(let message):
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

    private var connectingContent: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Подключаем iCloud…")
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

            Button("Повторить") {
                Task { await model.retryWelcome() }
            }
            .buttonStyle(OneCartPrimaryButtonStyle())
        }
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task { await model.completeAppleSignIn(authorization: authorization) }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            model.reportWelcomeFailure(
                (error as? LocalizedError)?.errorDescription
                    ?? "Не удалось войти через Apple."
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
                    Text("У вас уже есть корзина «\(prompt.privateFamilyName)», а семья поделилась «\(prompt.sharedFamilyName)».")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("В вашей корзине", systemImage: "cart")
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
                            Label("Перенести товары в семейную", systemImage: "arrow.right.arrow.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OneCartPrimaryButtonStyle())

                        Button {
                            Task {
                                await model.applyCartMergeChoice(.useSharedOnly)
                                dismiss()
                            }
                        } label: {
                            Label("Использовать только семейную", systemImage: "person.3.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OneCartSecondaryButtonStyle())

                        Button {
                            Task {
                                await model.applyCartMergeChoice(.keepPrivate)
                                dismiss()
                            }
                        } label: {
                            Text("Оставить мою корзину")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(OneCartPalette.background)
            .navigationTitle("Объединить корзины")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled()
    }

    private func summaryText(_ summary: FamilySpaceContentSummary) -> String {
        var parts: [String] = []
        if summary.productCount > 0 {
            parts.append("\(summary.productCount) товаров")
        }
        if summary.storeCount > 0 {
            parts.append("\(summary.storeCount) магазинов")
        }
        if summary.historyCount > 0 {
            parts.append("\(summary.historyCount) покупок в истории")
        }
        return parts.isEmpty ? "Пустая стартовая корзина" : parts.joined(separator: ", ")
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

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.onRequest = onRequest
        context.coordinator.onCompletion = onCompletion
    }

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding {
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
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            onCompletion(.success(authorization))
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            onCompletion(.failure(error))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            AppleSignInPresentationAnchor.current
        }
    }
}
