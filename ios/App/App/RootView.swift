import SwiftUI

enum OneCartPalette {
    static let primary = Color(red: 52 / 255, green: 120 / 255, blue: 91 / 255)
    static let primaryStrong = Color(red: 40 / 255, green: 95 / 255, blue: 71 / 255)
    static let primarySoft = Color(red: 225 / 255, green: 239 / 255, blue: 231 / 255)
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let danger = Color(red: 185 / 255, green: 74 / 255, blue: 72 / 255)
}

private enum RootPhase: Equatable {
    case loading
    case launchError
    case authentication
    case familySetup
    case main
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: RootPhase {
        if !model.isReady {
            return .loading
        }
        if model.launchError != nil {
            return .launchError
        }
        if model.account == nil {
            return .authentication
        }
        if model.familySpaces.isEmpty {
            return .familySetup
        }
        return .main
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                switch phase {
                case .loading:
                    LaunchLoadingView()
                        .transition(.opacity)
                case .launchError:
                    LaunchErrorView(message: model.launchError ?? "")
                        .transition(.opacity)
                case .authentication:
                    AuthenticationView()
                        .transition(.opacity)
                case .familySetup:
                    FamilySetupView()
                        .transition(.opacity)
                case .main:
                    MainTabView()
                        .transition(.opacity)
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.28),
                value: phase
            )

            if let toast = model.toast {
                ToastBanner(message: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .sheet(isPresented: $model.familyManagementPresented) {
            FamilyManagementSheet()
        }
        .sheet(item: $model.familyInvitePreview) { preview in
            FamilyInviteAcceptanceSheet(preview: preview)
        }
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            OneCartMark()
            ProgressView("Подготавливаем ваши списки…")
                .tint(OneCartPalette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneCartPalette.background)
    }
}

private struct LaunchErrorView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundColor(.orange)
            Text("OneCart не удалось запустить")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Повторить") {
                Task { await model.retryStartup() }
            }
            .buttonStyle(OneCartPrimaryButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OneCartPalette.background)
    }
}

private enum AuthenticationMode: String, CaseIterable, Identifiable {
    case signIn = "Вход"
    case register = "Регистрация"

    var id: String { rawValue }
}

private struct AuthenticationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var mode: AuthenticationMode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var localMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        OneCartMark()
                        Text("Покупки всей семьи — в одном месте")
                            .font(.largeTitle.bold())
                        Text("Войдите в OneCart, чтобы списки работали на ваших устройствах и у приглашённых членов семьи.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if model.hasPendingFamilyInvite {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .foregroundColor(OneCartPalette.primaryStrong)
                                .frame(width: 36, height: 36)
                                .background(OneCartPalette.primarySoft, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Вас пригласили в семью")
                                    .font(.subheadline.weight(.semibold))
                                Text("Войдите или создайте аккаунт — приглашение откроется автоматически.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .oneCartCard()
                    }

                    Picker("Режим", selection: $mode) {
                        ForEach(AuthenticationMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _ in
                        localMessage = nil
                        model.clearAuthenticationMessage()
                    }

                    VStack(spacing: 14) {
                        if mode == .register {
                            TextField("Ваше имя", text: $displayName)
                                .textContentType(.name)
                                .submitLabel(.next)
                        }

                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .submitLabel(.next)

                        SecureField("Пароль", text: $password)
                            .textContentType(mode == .register ? .newPassword : .password)
                            .submitLabel(mode == .register ? .next : .go)

                        if mode == .register {
                            SecureField("Повторите пароль", text: $passwordConfirmation)
                                .textContentType(.newPassword)
                                .submitLabel(.go)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .oneCartCard()

                    if let message = localMessage ?? model.authenticationMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(OneCartPalette.primary)
                            Text(message)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .oneCartCard()
                    }

                    Button {
                        submit()
                    } label: {
                        HStack {
                            if model.isBusy {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(mode == .signIn ? "Войти" : "Создать аккаунт")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OneCartPrimaryButtonStyle())
                    .disabled(model.isBusy)

                    Label(
                        "Продукты можно добавлять без интернета. OneCart отправит изменения на сервер, когда сеть появится.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(OneCartPalette.background)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }

    private func submit() {
        localMessage = nil
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.contains("@") else {
            localMessage = "Введите корректный email."
            return
        }
        guard !password.isEmpty else {
            localMessage = "Введите пароль."
            return
        }

        if mode == .register {
            guard password == passwordConfirmation else {
                localMessage = "Пароли не совпадают."
                return
            }
            Task {
                await model.register(
                    displayName: displayName,
                    email: normalizedEmail,
                    password: password
                )
            }
        } else {
            Task { await model.signIn(email: normalizedEmail, password: password) }
        }
    }
}

struct FamilySetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var familyName = "Наша семья"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        OneCartMark()
                        Text("Создайте семейное пространство")
                            .font(.largeTitle.bold())
                        if let account = model.account {
                            Text("Вы вошли как \(account.displayName) · \(account.email)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !model.pendingInvitations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Вас пригласили")
                                .font(.headline)
                            ForEach(model.pendingInvitations) { invitation in
                                InvitationRow(invitation: invitation)
                            }
                        }
                        .oneCartCard()
                    }

                    if model.hasPendingFamilyInvite {
                        Button {
                            Task { await model.showPendingFamilyInvite() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.open.fill")
                                    .foregroundColor(OneCartPalette.primaryStrong)
                                    .frame(width: 36, height: 36)
                                    .background(OneCartPalette.primarySoft, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Открыть приглашение")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Посмотрите семью перед присоединением")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .oneCartCard()
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Своё пространство", systemImage: "person.3.fill")
                            .font(.headline)
                            .foregroundColor(OneCartPalette.primaryStrong)
                        TextField("Наша семья", text: $familyName)
                            .textFieldStyle(.roundedBorder)
                        Text("Вы станете владельцем и сможете приглашать близких обычной ссылкой.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .oneCartCard()

                    Button {
                        Task { await model.createFamilySpace(name: familyName) }
                    } label: {
                        HStack {
                            if model.isBusy {
                                ProgressView().tint(.white)
                            }
                            Label("Создать семейный список", systemImage: "plus")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OneCartPrimaryButtonStyle())
                    .disabled(
                        model.isBusy
                            || familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Button("Выйти из аккаунта") {
                        Task { await model.signOut() }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.secondary)
                }
                .padding(20)
            }
            .background(OneCartPalette.background)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

struct InvitationRow: View {
    @EnvironmentObject private var model: AppModel
    let invitation: FamilyInvitation

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "envelope.open.fill")
                .foregroundColor(OneCartPalette.primary)
                .frame(width: 34, height: 34)
                .background(OneCartPalette.primarySoft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(invitation.familyName)
                    .font(.subheadline.weight(.semibold))
                Text("Приглашает \(invitation.invitedByName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Принять") {
                Task { await model.acceptInvitation(invitation) }
            }
            .font(.subheadline.weight(.semibold))
            .disabled(model.isBusy)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsSyncStatus: Bool {
        model.syncState != .synchronized
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSyncStatus {
                SyncStatusBar(state: model.syncState)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.22),
                        value: model.syncState
                    )
            }
            if model.hasPendingFamilyInvite {
                PendingLinkInvitationBanner()
            }
            if !model.pendingInvitations.isEmpty {
                PendingInvitationBanner(count: model.pendingInvitations.count)
            }
            TabView {
                HomeView()
                    .tabItem { Label("Главная", systemImage: "cart.fill") }
                StoresView()
                    .tabItem { Label("Магазины", systemImage: "storefront.fill") }
                HistoryView()
                    .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
                SettingsView()
                    .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
            }
            .tint(OneCartPalette.primary)
        }
        .background(OneCartPalette.background)
    }
}

private struct PendingLinkInvitationBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            Task { await model.showPendingFamilyInvite() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                Text("Открыть приглашение в семью")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundColor(OneCartPalette.primaryStrong)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(OneCartPalette.primarySoft)
        }
        .buttonStyle(.plain)
    }
}

private struct PendingInvitationBanner: View {
    @EnvironmentObject private var model: AppModel
    let count: Int

    var body: some View {
        Button {
            model.showFamilyManagement()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "envelope.badge.fill")
                Text(count == 1 ? "Новое приглашение в семью" : "Новых приглашений: \(count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundColor(OneCartPalette.primaryStrong)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(OneCartPalette.primarySoft)
        }
        .buttonStyle(.plain)
    }
}

struct SyncStatusBar: View {
    let state: OneCartSyncState

    var body: some View {
        HStack(spacing: 8) {
            if state == .syncing {
                ProgressView()
                    .scaleEffect(0.72)
            } else {
                Image(systemName: state.systemImage)
                    .font(.caption.weight(.semibold))
            }
            Text(state.title)
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(backgroundColor)
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    private var foregroundColor: Color {
        switch state {
        case .synchronized, .syncing: return OneCartPalette.primaryStrong
        case .offline: return .secondary
        case .failed: return OneCartPalette.danger
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .synchronized, .syncing: return OneCartPalette.primarySoft
        case .offline: return Color(.tertiarySystemFill)
        case .failed: return OneCartPalette.danger.opacity(0.12)
        }
    }
}

struct OneCartMark: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cart.fill")
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(OneCartPalette.primary, in: RoundedRectangle(cornerRadius: 12))
            Text("OneCart")
                .font(.title2.bold())
        }
    }
}

struct ToastBanner: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.style.systemImage)
                .foregroundColor(accentColor)
            Text(message.text)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    private var accentColor: Color {
        switch message.style {
        case .success: return OneCartPalette.primary
        case .info: return .blue
        case .error: return OneCartPalette.danger
        }
    }
}

struct OneCartPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                configuration.isPressed
                    ? OneCartPalette.primaryStrong
                    : OneCartPalette.primary,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct OneCartSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(OneCartPalette.primaryStrong)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                OneCartPalette.primarySoft.opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

extension View {
    func oneCartCard() -> some View {
        padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}
