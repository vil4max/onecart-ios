import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingProfile = false
    @State private var showingHistory = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    accountCard
                    familyCard
                    historyCard

                    PreferencesSettingsSection(preferences: model.preferences)

                    signOutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingProfile) {
                if let account = model.account {
                    ProfileEditorSheet(
                        account: account,
                        avatar: model.profileAvatar,
                        banner: model.profileBanner
                    )
                }
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView()
                    .environmentObject(model)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Account / Profile

    private var signOutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionLabel(title: "Аккаунт")
            Button(role: .destructive) {
                model.signOut()
            } label: {
                Label("Выйти из Apple ID", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(16)
            .background(
                OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private var accountCard: some View {
        Button {
            showingProfile = true
        } label: {
            VStack(spacing: 0) {
                ProfileBannerView(
                    image: model.profileBanner,
                    remoteURL: model.account?.bannerURL,
                    height: 88,
                    useAppDefaultWhenEmpty: true
                )

                HStack(spacing: 14) {
                    if let account = model.account {
                        ProfileAvatarView(
                            name: account.displayName,
                            image: model.profileAvatar,
                            remoteURL: account.avatarURL,
                            size: 56
                        )
                        .overlay(
                            Circle()
                                .stroke(OneCartPalette.surface, lineWidth: 3)
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Личный профиль")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("Открыть профиль")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(OneCartPalette.primary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .background(
                OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открывает редактирование профиля")
    }

    // MARK: - Family

    private var familyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(title: "Семья")

            VStack(spacing: 0) {
                Button {
                    model.showFamilyManagement()
                } label: {
                    SettingsActionRow(
                        image: model.access?.isOwner == true
                            ? "person.badge.plus"
                            : "person.2.fill",
                        title: model.access?.isOwner == true ? "Пригласить семью" : "Участники",
                        detail: familyMembersDetail,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                if model.familySpaces.isEmpty {
                    settingsDivider
                    SettingsActionRow(
                        image: "arrow.triangle.2.circlepath.icloud",
                        title: "Подключаем корзину…",
                        detail: "Подождите немного",
                        showsChevron: false
                    )
                    .task {
                        await model.ensureHouseholdCartIfNeeded()
                    }
                }
            }
            .background(
                OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(title: "Покупки")

            Button {
                showingHistory = true
            } label: {
                SettingsActionRow(
                    image: "clock.arrow.circlepath",
                    title: "История",
                    detail: model.history.isEmpty
                        ? "Пока пусто"
                        : "\(model.history.count)",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .background(
                OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    // MARK: - Helpers

    private var settingsDivider: some View {
        Divider().padding(.leading, 58)
    }

    private var familyMembersDetail: String {
        let count = max(model.familyMembers.count, model.activeFamilySpace == nil ? 0 : 1)
        if count <= 1 {
            return model.access?.isOwner == true
                ? "Поделитесь корзиной через Share"
                : "Только вы"
        }
        return memberCountText(count)
    }
}

struct FamilyManagementSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: SettingsViewModel
    @State private var familyName = ""
    @State private var confirmingLeave = false
    @State private var memberToRemove: FamilyMember?
    @State private var inviteLink: FamilyInviteLink?
    @State private var sharePayload: FamilySharePayload?
    @State private var preparingInviteAction: InviteLinkAction?
    @State private var didCopyLink = false
    @State private var alertMessage: String?

    init(model: AppModel) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(session: model))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    familyHeader

                    if model.access?.isOwner == true {
                        inviteCard
                    }

                    memberSection

                    if model.access?.isOwner == true {
                        familySettingsCard
                    }

                    if model.access?.isParticipant == true {
                        Button(role: .destructive) {
                            confirmingLeave = true
                        } label: {
                            Label(
                                "Покинуть эту группу",
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
            .navigationTitle("Группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert(
                "OneCart",
                isPresented: Binding(
                    get: { alertMessage != nil },
                    set: { if !$0 { alertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    alertMessage = nil
                }
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                updateFamilyName()
                if inviteLink == nil {
                    inviteLink = model.preparedInviteLink
                }
            }
            .onChange(of: model.activeFamilySpace?.id) { _ in
                inviteLink = model.preparedInviteLink
                updateFamilyName()
            }
            .onChange(of: model.preparedInviteLink?.id) { _ in
                if let prepared = model.preparedInviteLink {
                    inviteLink = prepared
                }
            }
            .sheet(item: $sharePayload) { payload in
                ActivityViewController(
                    activityItems: [FamilyInviteActivityItem(link: payload.link)]
                )
            }
            .alert("Покинуть группу?", isPresented: $confirmingLeave) {
                Button("Отмена", role: .cancel) {}
                Button("Покинуть", role: .destructive) {
                    Task {
                        await viewModel.leaveCurrentFamily()
                        dismiss()
                    }
                }
            } message: {
                Text("Список исчезнет из вашего аккаунта. Данные остальных участников не изменятся.")
            }
            .alert(item: $memberToRemove) { member in
                Alert(
                    title: Text("Удалить участника?"),
                    message: Text("\(member.displayName) потеряет доступ к этой группе."),
                    primaryButton: .destructive(Text("Удалить")) {
                        Task { await viewModel.removeMember(member) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .navigationViewStyle(.stack)
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
                Text(model.activeFamilySpace?.displayName ?? "Группа")
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
                Text("Пригласить в группу")
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
                    HStack(spacing: 8) {
                        if preparingInviteAction == .share {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Пригласить")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OneCartPrimaryButtonStyle())

                Button {
                    prepareInviteLink(action: .copy)
                } label: {
                    ZStack {
                        if preparingInviteAction == .copy {
                            ProgressView()
                                .tint(OneCartPalette.primaryStrong)
                        } else {
                            Image(systemName: didCopyLink ? "checkmark" : "doc.on.doc")
                                .font(.body.weight(.semibold))
                                .foregroundColor(OneCartPalette.primaryStrong)
                                .scaleEffect(didCopyLink ? 1.14 : 1)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(OneCartSecondaryButtonStyle())
                .accessibilityLabel(didCopyLink ? "Ссылка скопирована" : "Скопировать ссылку")
                .animation(
                    reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                    value: didCopyLink
                )
            }
            .disabled(preparingInviteAction != nil || !model.isOnline)

            if !model.isOnline {
                Label(
                    "Приглашения доступны только онлайн. Подключитесь к интернету, чтобы поделиться ссылкой.",
                    systemImage: "wifi.slash"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Label("Доступом и участниками управляет владелец пространства.", systemImage: "lock.fill")
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
                if model.isFamilyMetadataLoading, model.familyMembers.isEmpty {
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
                            if model.access?.isOwner == true, !member.isCurrentUser {
                                Button(role: .destructive) {
                                    memberToRemove = member
                                } label: {
                                    Label("Удалить из группы", systemImage: "person.fill.xmark")
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

    private var familySettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Название группы", systemImage: "pencil")
                .font(.headline)
            TextField("Название группы", text: $familyName)
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
                access: model.access ?? .owner,
                joinedAt: model.activeFamilySpace?.createdAt ?? Date(),
                isCurrentUser: true,
                avatarURL: account.avatarURL,
                bannerURL: account.bannerURL
            ),
        ]
    }

    private func prepareInviteLink(action: InviteLinkAction) {
        guard preparingInviteAction == nil else { return }
        preparingInviteAction = action

        let inviteTask = Task { @MainActor in
            defer {
                if preparingInviteAction == action {
                    preparingInviteAction = nil
                }
            }

            let link: FamilyInviteLink
            do {
                if let cached = inviteLink, cached.expiresAt > Date().addingTimeInterval(30) {
                    link = cached
                } else {
                    let created = try await viewModel.createFamilyInviteLink()
                    guard !Task.isCancelled else { return }
                    inviteLink = created
                    link = created
                }
            } catch is CancellationError {
                return
            } catch {
                alertMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                return
            }

            // Clear spinner before share sheet / copy checkmark so the loader cannot stick.
            preparingInviteAction = nil
            guard !Task.isCancelled else { return }

            switch action {
            case .share:
                sharePayload = FamilySharePayload(link: link)
            case .copy:
                UIPasteboard.general.setItems(
                    [[
                        UTType.plainText.identifier: link.shareMessage,
                        UTType.url.identifier: link.url,
                    ]],
                    options: [:]
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7)) {
                    didCopyLink = true
                }
                try? await Task.sleep(nanoseconds: 1_250_000_000)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    didCopyLink = false
                }
            }
        }

        // Hard UI ceiling: even if CloudKit never resumes a continuation, stop the spinner.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 24_000_000_000)
            guard !inviteTask.isCancelled else { return }
            guard preparingInviteAction == action else { return }
            inviteTask.cancel()
            preparingInviteAction = nil
            alertMessage = OneCartCloudKitError.shareTimedOut.errorDescription
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

private final class FamilyInviteActivityItem: NSObject, UIActivityItemSource {
    let link: FamilyInviteLink

    init(link: FamilyInviteLink) {
        self.link = link
    }

    func activityViewControllerPlaceholderItem(
        _: UIActivityViewController
    ) -> Any {
        link.url
    }

    func activityViewController(
        _: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        if activityType == .mail || activityType == .message || activityType == .postToFacebook {
            return link.shareMessage
        }
        return link.url
    }

    func activityViewControllerLinkMetadata(
        _: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = link.url
        metadata.url = link.url
        metadata.title = link.shareTitle
        let image = OneCartShareBranding.thumbnailImage
        metadata.iconProvider = NSItemProvider(object: image)
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }

    func activityViewController(
        _: UIActivityViewController,
        subjectForActivityType _: UIActivity.ActivityType?
    ) -> String {
        link.shareTitle
    }
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

private struct FamilyMemberProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false
    let member: FamilyMember

    /// Prefer live family RPC URL; for self also fall back to account / local banner.
    private var resolvedBannerURL: String? {
        if let url = member.bannerURL, !url.isEmpty {
            return url
        }
        if member.isCurrentUser {
            return model.account?.bannerURL
        }
        return nil
    }

    private var resolvedBannerImage: UIImage? {
        member.isCurrentUser ? model.profileBanner : nil
    }

    private var resolvedAvatarURL: String? {
        if let url = member.avatarURL, !url.isEmpty {
            return url
        }
        if member.isCurrentUser {
            return model.account?.avatarURL
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Always: custom banner, remote URL from family RPC, or app default.
                ProfileBannerView(
                    image: resolvedBannerImage,
                    remoteURL: resolvedBannerURL,
                    height: 148,
                    useAppDefaultWhenEmpty: true
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    ProfileAvatarView(
                        name: member.displayName,
                        image: member.isCurrentUser ? model.profileAvatar : nil,
                        remoteURL: resolvedAvatarURL,
                        size: 104
                    )
                    .overlay(
                        Circle()
                            .stroke(OneCartPalette.background, lineWidth: 4)
                    )
                    .offset(y: -40)
                    .padding(.bottom, -40)

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
                        Text("Участник пространства")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 0) {
                        ProfileDetailRow(title: "Роль", value: member.access.title)
                        Divider().padding(.leading, 16)
                        ProfileDetailRow(
                            title: "В группе с",
                            value: FamilyDateFormatter.string(from: member.joinedAt)
                        )
                    }
                    .background(
                        OneCartPalette.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                    if model.access?.isOwner == true, !member.isCurrentUser {
                        Button(role: .destructive) {
                            confirmingRemoval = true
                        } label: {
                            Label("Удалить из группы", systemImage: "person.fill.xmark")
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
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
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
            Text("\(member.displayName) потеряет доступ к этой группе.")
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
    let noun = if remainder100 >= 11, remainder100 <= 14 {
        "участников"
    } else if remainder10 == 1 {
        "участник"
    } else if remainder10 >= 2, remainder10 <= 4 {
        "участника"
    } else {
        "участников"
    }
    return "\(count) \(noun)"
}

private struct PreferencesSettingsSection: View {
    @ObservedObject var preferences: DevicePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionLabel(title: String(localized: "settings.appearance"))

            VStack(spacing: 0) {
                SettingsPickerRow(
                    image: "circle.lefthalf.filled",
                    title: String(localized: "settings.theme")
                ) {
                    Picker(String(localized: "settings.theme"), selection: $preferences.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(OneCartPalette.primaryStrong)
                }

                Divider().padding(.leading, 58)

                SettingsPickerRow(
                    image: "plus.forwardslash.minus",
                    title: String(localized: "settings.unit")
                ) {
                    Picker(String(localized: "settings.unit"), selection: $preferences.defaultUnit) {
                        ForEach(ProductUnit.allCases) { unit in
                            Text(unit.localizedName).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(OneCartPalette.primaryStrong)
                }
            }
            .background(
                OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }
}

private struct SettingsSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(OneCartPalette.primary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingsActionRow: View {
    let image: String
    let title: String
    let detail: String?
    var showsChevron: Bool = true
    var chevron: String = "chevron.right"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: image)
                .font(.body.weight(.semibold))
                .foregroundColor(OneCartPalette.primary)
                .frame(width: 34, height: 34)
                .background(OneCartPalette.primarySoft, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: chevron)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

private struct SettingsPickerRow<Content: View>: View {
    let image: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: image)
                .font(.body.weight(.semibold))
                .foregroundColor(OneCartPalette.primary)
                .frame(width: 34, height: 34)
                .background(OneCartPalette.primarySoft, in: Circle())
                // Keep the icon chip from shifting when the menu value reflows.
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            content
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: 168, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 56, maxHeight: 56, alignment: .center)
        .clipped()
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
                Text(member.access.isOwner ? "Владелец пространства" : "Участник пространства")
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
    @EnvironmentObject private var model: AppModel
    let member: FamilyMember
    let size: CGFloat

    var body: some View {
        ProfileAvatarView(
            name: member.displayName,
            image: member.isCurrentUser ? model.profileAvatar : nil,
            remoteURL: member.avatarURL,
            size: size
        )
    }
}
