import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 14) {
                OneCartMark()
                Text("Войдите с Apple")
                    .font(.largeTitle.bold())
                Text("OneCart использует ваш Apple ID для безопасного входа и синхронизирует списки через iCloud.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isSigningIn)

                if isSigningIn {
                    ProgressView("Вход…")
                        .font(.footnote)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(OneCartPalette.danger)
                        .multilineTextAlignment(.center)
                }
            }

            Text("Убедитесь, что на устройстве включён вход в Apple Account и iCloud.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneCartPalette.background)
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            isSigningIn = true
            errorMessage = nil
            Task {
                await model.completeAppleSignIn(authorization: authorization)
                isSigningIn = false
                if let launchError = model.launchError {
                    errorMessage = launchError
                }
            }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Не удалось войти через Apple."
        }
    }
}
