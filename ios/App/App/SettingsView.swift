import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingCreateSpace = false
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationView {
            Form {
                Section("Аккаунт OneCart") {
                    if let account = model.account {
                        SettingsRow(
                            image: "person.crop.circle.fill",
                            title: account.displayName,
                            detail: account.email,
                            trailingImage: nil
                        )
                    }

                    SettingsRow(
                        image: model.syncState.systemImage,
                        title: model.syncState.title,
                        detail: syncDetail,
                        trailingImage: nil
                    )

                    Button {
                        Task { await model.refreshFromServer() }
                    } label: {
                        Label("Синхронизировать сейчас", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy || !model.isOnline)
                }

                Section("Семейное пространство") {
                    if let active = model.activeFamilySpace {
                        if model.familySpaces.count > 1 {
                            Picker("Текущая семья", selection: activeFamilyBinding) {
                                ForEach(model.familySpaces, id: \.objectID) { space in
                                    Text(space.displayName).tag(space.id)
                                }
                            }
                        } else {
                            SettingsRow(
                                image: "person.3.fill",
                                title: active.displayName,
                                detail: model.access?.title ?? "Семейное пространство",
                                trailingImage: nil
                            )
                        }

                        Button {
                            model.showFamilyManagement()
                        } label: {
                            HStack {
                                Label("Участники семьи", systemImage: "person.3.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Button {
                        showingCreateSpace = true
                    } label: {
                        Label("Создать ещё одну семью", systemImage: "plus.circle")
                    }
                }

                if !model.pendingInvitations.isEmpty {
                    Section("Приглашения для вас") {
                        ForEach(model.pendingInvitations) { invitation in
                            InvitationRow(invitation: invitation)
                        }
                    }
                }

                PreferencesSettingsSection(preferences: model.preferences)

                Section("О синхронизации") {
                    Text("OneCart хранит рабочую копию списков на iPhone и синхронизирует её через защищённый Supabase-сервер. Доступ к данным ограничен участниками вашей семьи.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Для входа используется email и пароль OneCart. Apple ID и подписка Apple Developer не нужны.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Выйти из аккаунта", role: .destructive) {
                        confirmingSignOut = true
                    }
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $showingCreateSpace) {
                CreateFamilySpaceSheet()
            }
            .alert("Выйти из OneCart?", isPresented: $confirmingSignOut) {
                Button("Отмена", role: .cancel) {}
                Button("Выйти", role: .destructive) {
                    Task { await model.signOut() }
                }
            } message: {
                Text("Локальная копия останется защищённой и снова появится после входа в этот аккаунт.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var activeFamilyBinding: Binding<UUID?> {
        Binding(
            get: { model.activeFamilySpace?.id },
            set: { id in
                guard let id,
                      let space = model.familySpaces.first(where: { $0.id == id }) else { return }
                model.setActiveFamilySpace(space)
            }
        )
    }

    private var syncDetail: String {
        if let error = model.lastSyncError, model.syncState == .failed {
            return error
        }
        switch model.syncState {
        case .synchronized:
            return "Изменения доступны участникам семьи."
        case .syncing:
            return "Обновляем сервер и локальную копию."
        case .offline:
            return "Можно продолжать добавлять продукты — они отправятся позже."
        case .failed:
            return "Локальные данные сохранены. Попробуйте повторить синхронизацию."
        }
    }
}

struct FamilyManagementSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var familyName = ""
    @State private var confirmingLeave = false
    @State private var memberToRemove: FamilyMember?
    @State private var inviteLink: FamilyInviteLink?
    @State private var sharePayload: FamilySharePayload?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.familySpaces.count > 1 {
                        familySwitcher
                    }

                    familyHeader

                    if model.access?.isOwner == true {
                        inviteCard
                    }

                    memberSection

                    if !model.pendingInvitations.isEmpty {
                        pendingInvitationsCard
                    }

                    if model.access?.isOwner == true {
                        familySettingsCard
                    }

                    if model.access?.isParticipant == true {
                        Button(role: .destructive) {
                            confirmingLeave = true
                        } label: {
                            Label(
                                "Покинуть эту семью",
                                systemImage: "rectangle.portrait.and.arrow.right"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(OneCartPalette.danger)
                            .background(
                                OneCartPalette.danger.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("Семья")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refreshFromServer() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!model.isOnline || model.isBusy)
                }
            }
            .onAppear { updateFamilyName() }
            .onChange(of: model.activeFamilySpace?.id) { _ in
                inviteLink = nil
                updateFamilyName()
            }
            .sheet(item: $sharePayload) { payload in
                ActivityViewController(
                    activityItems: [payload.link.shareMessage]
                )
            }
            .alert("Покинуть семейное пространство?", isPresented: $confirmingLeave) {
                Button("Отмена", role: .cancel) {}
                Button("Покинуть", role: .destructive) {
                    Task {
                        await model.leaveCurrentFamily()
                        dismiss()
                    }
                }
            } message: {
                Text("Список исчезнет из вашего аккаунта. Данные остальных участников не изменятся.")
            }
            .alert(item: $memberToRemove) { member in
                Alert(
                    title: Text("Удалить участника?"),
                    message: Text("\(member.displayName) потеряет доступ к этому семейному пространству."),
                    primaryButton: .destructive(Text("Удалить")) {
                        Task { await model.removeMember(member) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    private var familySwitcher: some View {
        Menu {
            ForEach(model.familySpaces, id: \.objectID) { space in
                Button {
                    model.setActiveFamilySpace(space)
                } label: {
                    if space.id == model.activeFamilySpace?.id {
                        Label(space.displayName, systemImage: "checkmark")
                    } else {
                        Text(space.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .foregroundColor(OneCartPalette.primary)
                    .frame(width: 38, height: 38)
                    .background(OneCartPalette.primarySoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Текущая семья")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.activeFamilySpace?.displayName ?? "Семья")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .oneCartCard()
        }
    }

    private var familyHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(OneCartPalette.primarySoft)
                    .frame(width: 82, height: 82)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(OneCartPalette.primaryStrong)
            }

            VStack(spacing: 5) {
                Text(model.activeFamilySpace?.displayName ?? "Семья")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(memberCountText(displayedMembers.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !displayedMembers.isEmpty {
                HStack(spacing: -8) {
                    ForEach(Array(displayedMembers.prefix(4).enumerated()), id: \.element.id) {
                        index, member in
                        FamilyAvatarView(member: member, size: 34)
                            .overlay(Circle().stroke(OneCartPalette.surface, lineWidth: 2))
                            .zIndex(Double(4 - index))
                    }
                    if displayedMembers.count > 4 {
                        Text("+\(displayedMembers.count - 4)")
                            .font(.caption2.bold())
                            .frame(width: 34, height: 34)
                            .background(Color(.tertiarySystemFill), in: Circle())
                            .overlay(Circle().stroke(OneCartPalette.surface, lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .oneCartCard()
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Пригласить в семью")
                    .font(.headline)
                Text("Отправьте ссылку в Telegram, Сообщениях или любом другом приложении.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    prepareInviteLink(action: .share)
                } label: {
                    Label("Пригласить", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OneCartPrimaryButtonStyle())

                Button {
                    prepareInviteLink(action: .copy)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(OneCartSecondaryButtonStyle())
                .accessibilityLabel("Скопировать ссылку")
            }
            .disabled(model.isBusy || !model.isOnline)

            Label("Ссылка одноразовая и действует 14 дней.", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .oneCartCard()
    }

    private var memberSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Участники")
                    .font(.headline)
                Spacer()
                Text("\(displayedMembers.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(OneCartPalette.primaryStrong)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(OneCartPalette.primarySoft, in: Capsule())
            }

            VStack(spacing: 0) {
                if model.isFamilyMetadataLoading && model.familyMembers.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(OneCartPalette.primary)
                        Text("Обновляем участников…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(Array(displayedMembers.enumerated()), id: \.element.id) {
                        index, member in
                        NavigationLink {
                            FamilyMemberProfileView(member: member)
                        } label: {
                            FamilyMemberRow(member: member)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if model.access?.isOwner == true && !member.isCurrentUser {
                                Button(role: .destructive) {
                                    memberToRemove = member
                                } label: {
                                    Label("Удалить из семьи", systemImage: "person.fill.xmark")
                                }
                            }
                        }

                        if index < displayedMembers.count - 1 {
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
            .background(
                OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private var pendingInvitationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Приглашения для вас")
                .font(.headline)
            ForEach(Array(model.pendingInvitations.enumerated()), id: \.element.id) {
                index, invitation in
                InvitationRow(invitation: invitation)
                if index < model.pendingInvitations.count - 1 {
                    Divider()
                }
            }
        }
        .oneCartCard()
    }

    private var familySettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Название семьи", systemImage: "pencil")
                .font(.headline)
            TextField("Название семьи", text: $familyName)
                .textFieldStyle(.roundedBorder)
            Button("Сохранить название") {
                Task { await model.renameFamilySpace(name: familyName) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(OneCartPalette.primaryStrong)
            .disabled(
                familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.isBusy
                    || familyName == model.activeFamilySpace?.displayName
            )
        }
        .oneCartCard()
    }

    private var displayedMembers: [FamilyMember] {
        if !model.familyMembers.isEmpty {
            return model.familyMembers
        }
        guard let account = model.account, model.activeFamilySpace != nil else { return [] }
        return [
            FamilyMember(
                id: account.id,
                displayName: account.displayName,
                email: account.email,
                access: model.access ?? .owner,
                joinedAt: model.activeFamilySpace?.createdAt ?? Date(),
                isCurrentUser: true
            ),
        ]
    }

    private func prepareInviteLink(action: InviteLinkAction) {
        Task {
            let link: FamilyInviteLink
            if let cached = inviteLink, cached.expiresAt > Date().addingTimeInterval(30) {
                link = cached
            } else if let created = await model.createFamilyInviteLink() {
                inviteLink = created
                link = created
            } else {
                return
            }

            switch action {
            case .share:
                sharePayload = FamilySharePayload(link: link)
            case .copy:
                UIPasteboard.general.string = link.url.absoluteString
                model.showToast("Ссылка скопирована")
            }
        }
    }

    private func updateFamilyName() {
        familyName = model.activeFamilySpace?.displayName ?? ""
    }
}

private enum InviteLinkAction {
    case share
    case copy
}

private struct FamilySharePayload: Identifiable {
    let id = UUID()
    let link: FamilyInviteLink
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(
        _: UIActivityViewController,
        context _: Context
    ) {}
}

struct FamilyInviteAcceptanceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let preview: FamilyInvitePreview

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(OneCartPalette.primarySoft)
                            .frame(width: 92, height: 92)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundColor(OneCartPalette.primaryStrong)
                    }

                    VStack(spacing: 8) {
                        Text("Присоединиться к семье?")
                            .font(.title2.bold())
                        Text(preview.familyName)
                            .font(.headline)
                        Text(memberCountText(preview.memberCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            "Вы получите общий доступ к магазинам, товарам и истории покупок.",
                            systemImage: "cart.fill"
                        )
                        Label(
                            "Изменения синхронизируются между участниками семьи.",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Label(
                            "Можно выйти из семьи в любой момент.",
                            systemImage: "lock.shield.fill"
                        )
                    }
                    .font(.subheadline)
                    .oneCartCard()

                    Button {
                        Task { await model.acceptFamilyInvite(preview) }
                    } label: {
                        HStack {
                            if model.isBusy {
                                ProgressView().tint(.white)
                            }
                            Text("Присоединиться")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OneCartPrimaryButtonStyle())
                    .disabled(model.isBusy || !model.isOnline)

                    Button("Не сейчас") {
                        model.dismissFamilyInvitePreview()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                    .disabled(model.isBusy)
                }
                .padding(24)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("Приглашение")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.isBusy)
        }
        .navigationViewStyle(.stack)
    }
}

private struct FamilyMemberProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false
    let member: FamilyMember

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                FamilyAvatarView(member: member, size: 104)

                VStack(spacing: 7) {
                    HStack(spacing: 7) {
                        Text(member.displayName)
                            .font(.title2.bold())
                        if member.isCurrentUser {
                            Text("вы")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(OneCartPalette.primaryStrong)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(OneCartPalette.primarySoft, in: Capsule())
                        }
                    }
                    if let email = member.email, !email.isEmpty {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 0) {
                    ProfileDetailRow(title: "Роль", value: member.access.title)
                    Divider().padding(.leading, 16)
                    ProfileDetailRow(
                        title: "В семье с",
                        value: FamilyDateFormatter.string(from: member.joinedAt)
                    )
                }
                .background(
                    OneCartPalette.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

                if model.access?.isOwner == true && !member.isCurrentUser {
                    Button(role: .destructive) {
                        confirmingRemoval = true
                    } label: {
                        Label("Удалить из семьи", systemImage: "person.fill.xmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(OneCartPalette.danger)
                            .background(
                                OneCartPalette.danger.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                }
            }
            .padding(20)
        }
        .background(OneCartPalette.background.ignoresSafeArea())
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Удалить участника?", isPresented: $confirmingRemoval) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                Task {
                    await model.removeMember(member)
                    dismiss()
                }
            }
        } message: {
            Text("\(member.displayName) потеряет доступ к семейному пространству.")
        }
    }
}

private struct ProfileDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
        .padding(16)
    }
}

private enum FamilyDateFormatter {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

private func memberCountText(_ count: Int) -> String {
    let remainder100 = count % 100
    let remainder10 = count % 10
    let noun: String
    if remainder100 >= 11 && remainder100 <= 14 {
        noun = "участников"
    } else if remainder10 == 1 {
        noun = "участник"
    } else if remainder10 >= 2 && remainder10 <= 4 {
        noun = "участника"
    } else {
        noun = "участников"
    }
    return "\(count) \(noun)"
}

private struct PreferencesSettingsSection: View {
    @ObservedObject var preferences: DevicePreferences

    var body: some View {
        Section("Личные настройки устройства") {
            Picker("Тема", selection: $preferences.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }

            Picker("Язык", selection: $preferences.locale) {
                ForEach(AppLocale.allCases) { locale in
                    Text(locale.title).tag(locale)
                }
            }

            Picker("Единица по умолчанию", selection: $preferences.defaultUnit) {
                ForEach(ProductUnit.allCases) { unit in
                    Text(unit.localizedName).tag(unit)
                }
            }

            TextField(
                "Ваше имя для отметок покупки",
                text: $preferences.participantDisplayName
            )
            Text("Это имя видно рядом с отметкой «куплено». По умолчанию используется имя аккаунта.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsRow: View {
    let image: String
    let title: String
    let detail: String
    let trailingImage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: image)
                .frame(width: 24)
                .foregroundColor(OneCartPalette.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailingImage {
                Image(systemName: trailingImage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FamilyMemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: 12) {
            FamilyAvatarView(member: member, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if member.isCurrentUser {
                        Text("вы")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(OneCartPalette.primaryStrong)
                    }
                }
                HStack(spacing: 5) {
                    Text(member.access.isOwner ? "Владелец" : "Участник")
                    if let email = member.email, !email.isEmpty {
                        Text("·")
                        Text(email)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct FamilyAvatarView: View {
    let member: FamilyMember
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(avatarColor, in: Circle())
            .accessibilityLabel(member.displayName)
    }

    private var initials: String {
        let words = member.displayName
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [
            OneCartPalette.primary,
            Color(red: 0.31, green: 0.48, blue: 0.72),
            Color(red: 0.69, green: 0.43, blue: 0.35),
            Color(red: 0.48, green: 0.39, blue: 0.67),
            Color(red: 0.29, green: 0.57, blue: 0.58),
        ]
        let scalarSum = member.displayName.unicodeScalars.reduce(0) {
            $0 + Int($1.value)
        }
        return colors[scalarSum % colors.count]
    }
}

private struct CreateFamilySpaceSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Новая семья"

    var body: some View {
        NavigationView {
            Form {
                Section("Название") {
                    TextField("Новая семья", text: $name)
                }
                Section {
                    Text("Новое пространство появится сразу и будет доступно офлайн. После синхронизации вы сможете отправить участникам обычную ссылку-приглашение.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Новая семья")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task {
                            await model.createFamilySpace(name: name)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
