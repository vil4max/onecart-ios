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
                Text(headerSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            content

            footerNote

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneCartPalette.background)
    }

    private var headerSubtitle: String {
        switch model.welcomePhase {
        case .awaitingInvite:
            return "Войдите выполнен. Откройте ссылку-приглашение, которую прислал владелец семейной корзины."
        default:
            return "Один Apple ID — одна общая корзина для всей семьи через iCloud."
        }
    }

    @ViewBuilder
    private var footerNote: some View {
        switch model.welcomePhase {
        case .awaitingInvite:
            EmptyView()
        default:
            Text("Нужен Apple ID и включённый iCloud на устройстве.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.welcomePhase {
        case .signIn:
            signInContent
        case .connecting:
            connectingContent
        case .awaitingInvite:
            awaitingInviteContent
        case .failed(let message):
            failedContent(message: message)
        }
    }

    private var signInContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                ForEach(FamilyJoinIntent.allCases) { intent in
                    joinIntentButton(intent)
                }
            }

            if model.preferences.familyJoinIntent != nil {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func joinIntentButton(_ intent: FamilyJoinIntent) -> some View {
        let isSelected = model.preferences.familyJoinIntent == intent
        return Button {
            model.chooseJoinIntent(intent)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: intent == .owner ? "house.fill" : "link")
                    .font(.title3)
                    .foregroundColor(OneCartPalette.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(intent.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(intent.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? OneCartPalette.primary : .secondary)
            }
            .padding(14)
            .background(
                isSelected ? OneCartPalette.primarySoft : OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var connectingContent: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Подключаем семейную корзину…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var awaitingInviteContent: some View {
        VStack(spacing: 14) {
            Label("Ждём приглашение", systemImage: "envelope.open.fill")
                .font(.headline)
                .foregroundColor(OneCartPalette.primaryStrong)

            Text("Откройте ссылку из iMessage, Telegram или почты. iCloud покажет системный диалог — нажмите «Принять».")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Я принял приглашение") {
                Task { await model.refreshInviteAcceptance() }
            }
            .buttonStyle(OneCartPrimaryButtonStyle())
        }
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
        guard model.preferences.familyJoinIntent != nil else {
            model.reportWelcomeFailure("Выберите, создаёте вы корзину или вас пригласили.")
            return
        }
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
