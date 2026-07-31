import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var viewModel: CartShareViewModel
    @State private var sharePayload: CartSharePayload?
    @State private var isSharing = false
    @State private var shareAlert: UserAlert?
    @State private var confirmingLeave = false
    @State private var memberToRemove: FamilyMember?
    @State private var confirmingSignOut = false
    @State private var confirmingRevokeInvite = false
    @State private var isEditingDisplayName = false
    @State private var isEditingCartName = false
    @State private var draftDisplayName = ""
    @State private var draftCartName = ""

    init(model: AppModel) {
        _viewModel = StateObject(wrappedValue: CartShareViewModel(session: model))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.activeFamilySpace != nil {
                        AccountCartStatusRow(
                            cartTitle: model.cartTitle,
                            roleLine: cartRoleLine
                        )
                    }

                    if model.isFamilyMetadataLoading, displayedMembers.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(OneCartPalette.primary)
                            Text("account.updating_members")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(displayedMembers) { member in
                            AccountMemberRow(member: member)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if model.access?.isOwner == true, !member.isCurrentUser {
                                        Button(role: .destructive) {
                                            memberToRemove = member
                                        } label: {
                                            Label("common.delete", systemImage: "person.fill.xmark")
                                        }
                                    }
                                }
                        }
                    }

                    if model.activeFamilySpace != nil {
                        Button {
                            shareCart()
                        } label: {
                            AccountActionRow(
                                titleKey: "account.share_cart",
                                systemImage: "square.and.arrow.up",
                                trailing: {
                                    if isSharing {
                                        ProgressView()
                                            .tint(OneCartPalette.primary)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSharing || !model.isOnline)

                        if model.access?.isOwner == true {
                            Button {
                                beginEditingCartName()
                            } label: {
                                AccountActionRow(
                                    titleKey: "account.rename_cart",
                                    systemImage: "pencil"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if model.access?.isOwner == true {
                            Button {
                                confirmingRevokeInvite = true
                            } label: {
                                AccountActionRow(
                                    titleKey: "account.revoke_invite",
                                    systemImage: "person.badge.minus"
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isBusy || !model.isOnline)
                        }

                        if model.access?.isParticipant == true {
                            Button {
                                confirmingLeave = true
                            } label: {
                                AccountActionRow(
                                    titleKey: "account.leave_cart",
                                    systemImage: "rectangle.portrait.and.arrow.right",
                                    style: .destructive
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("settings.cart_section")
                } footer: {
                    Text(cartSectionFooter)
                }

                Section {
                    if let account = model.account {
                        Button {
                            beginEditingDisplayName()
                        } label: {
                            HStack(spacing: 12) {
                                ProfileAvatarView(
                                    name: account.displayName,
                                    remoteURL: account.avatarURL,
                                    size: 44
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.displayName)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("settings.apple_siwa_caption")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text(
                                        needsAccountName
                                            ? String(localized: "settings.apple_set_name")
                                            : String(localized: "settings.apple_edit_name")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("account.edit_display_name"))
                    }

                    Button {
                        confirmingSignOut = true
                    } label: {
                        AccountActionRow(
                            titleKey: "account.sign_out",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            style: .destructive
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("settings.apple_section")
                } footer: {
                    Text("settings.apple_name_footer")
                }
            }
            .listStyle(.insetGrouped)
            .tint(OneCartPalette.primary)
            .navigationTitle("settings.nav_title")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                MemberJoinNotifier.requestAuthorizationIfNeeded()
                await model.refreshAccountSharing()
            }
            .sheet(isPresented: $isEditingDisplayName) {
                NavigationStack {
                    Form {
                        Section {
                            TextField(
                                String(localized: "account.display_name_placeholder"),
                                text: $draftDisplayName
                            )
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        } footer: {
                            Text("account.display_name_prompt")
                        }
                    }
                    .navigationTitle("account.edit_display_name")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { isEditingDisplayName = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("account.display_name_save") {
                                let name = draftDisplayName
                                isEditingDisplayName = false
                                Task { await model.updateParticipantDisplayName(name) }
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isEditingCartName) {
                NavigationStack {
                    Form {
                        Section {
                            TextField(
                                String(localized: "account.cart_name_placeholder"),
                                text: $draftCartName
                            )
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        } footer: {
                            Text(
                                {
                                    if let family = model.activeFamilySpace,
                                       model.persistence.scope(for: family) == .private
                                    {
                                        return String(localized: "account.cart_name_prompt_personal")
                                    }
                                    return String(localized: "account.cart_name_prompt")
                                }()
                            )
                        }
                    }
                    .navigationTitle("account.rename_cart")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { isEditingCartName = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("account.cart_name_save") {
                                let name = draftCartName
                                isEditingCartName = false
                                Task { await model.renameActiveCart(name) }
                            }
                            .disabled(draftCartName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $sharePayload) { payload in
                CartActivityViewController(
                    activityItems: [CartInviteActivityItem(link: payload.link)]
                )
            }
            .alert(
                shareAlert?.kind.title ?? "",
                isPresented: Binding(
                    get: { shareAlert != nil },
                    set: { if !$0 { shareAlert = nil } }
                )
            ) {
                Button("common.ok", role: .cancel) { shareAlert = nil }
            } message: {
                Text(shareAlert?.message ?? "")
            }
            .alert("account.leave_confirm_title", isPresented: $confirmingLeave) {
                Button("common.cancel", role: .cancel) {}
                Button("account.leave_confirm_action", role: .destructive) {
                    Task { await viewModel.leaveCurrentFamily() }
                }
            } message: {
                Text("account.leave_confirm_message")
            }
            .alert("account.revoke_invite_title", isPresented: $confirmingRevokeInvite) {
                Button("common.cancel", role: .cancel) {}
                Button("account.revoke_invite_confirm", role: .destructive) {
                    Task { await model.revokeInviteLink() }
                }
            } message: {
                Text("account.revoke_invite_message")
            }
            .alert(
                "account.remove_member_title",
                isPresented: Binding(
                    get: { memberToRemove != nil },
                    set: { if !$0 { memberToRemove = nil } }
                ),
                presenting: memberToRemove
            ) { member in
                Button("common.delete", role: .destructive) {
                    Task { await viewModel.removeMember(member) }
                }
                Button("common.cancel", role: .cancel) {}
            } message: { member in
                Text("account.remove_member_message \(member.displayName)")
            }
            .alert("account.sign_out_confirm_title", isPresented: $confirmingSignOut) {
                Button("common.cancel", role: .cancel) {}
                Button("account.sign_out", role: .destructive) {
                    model.signOut()
                }
            } message: {
                Text("account.sign_out_message")
            }
        }
    }

    private var needsAccountName: Bool {
        ParticipantDisplayName.isPlaceholder(model.account?.displayName)
    }

    private var cartRoleLine: String {
        if model.access?.isParticipant == true {
            String(localized: "account.role_member_status")
        } else {
            String(localized: "account.role_owner_status")
        }
    }

    private var cartSectionFooter: String {
        if model.access?.isParticipant == true {
            String(localized: "account.cart_status_member_footer")
        } else if model.access?.isOwner == true {
            String(localized: "account.share_link_warning")
        } else {
            String(localized: "account.cart_status_owner_footer")
        }
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

    private func beginEditingDisplayName() {
        draftDisplayName = model.preferences.participantDisplayName.isEmpty
            ? (ParticipantDisplayName.isPlaceholder(model.account?.displayName)
                ? ""
                : (model.account?.displayName ?? ""))
            : model.preferences.participantDisplayName
        isEditingDisplayName = true
    }

    private func beginEditingCartName() {
        draftCartName = model.activeFamilySpace?.displayName ?? model.cartTitle
        isEditingCartName = true
    }

    private func shareCart() {
        guard !isSharing else { return }
        isSharing = true
        CartHaptics.light()
        CartSyncLog.action.info("shareCart UI start")
        let work = Task { @MainActor in
            defer { isSharing = false }
            do {
                let link: FamilyInviteLink = if let cached = model.preparedInviteLink,
                                                cached.expiresAt > Date().addingTimeInterval(30)
                {
                    cached
                } else {
                    try await model.createFamilyInviteLink()
                }
                guard !Task.isCancelled else { return }
                sharePayload = CartSharePayload(link: link)
                CartHaptics.success()
                CartSyncLog.action.info(
                    "shareCart UI done host=\(link.url.host ?? "-", privacy: .public)"
                )
            } catch is CancellationError {
                CartSyncLog.action.info("shareCart UI cancelled")
                return
            } catch {
                CartSyncLog.action.error(
                    "shareCart UI fail error=\(error.localizedDescription, privacy: .public)"
                )
                CartHaptics.error()
                if CloudKitUserFacingError.isProductionSchemaFailure(error) {
                    shareAlert = .error(CloudKitUserFacingError.productionSchemaMissing)
                } else {
                    shareAlert = .error(model.userFacingMessage(for: error))
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 24_000_000_000)
            guard !work.isCancelled else { return }
            if isSharing {
                work.cancel()
                isSharing = false
                CartSyncLog.action.error("shareCart UI timeout")
                if let message = OneCartCloudKitError.shareTimedOut.errorDescription {
                    shareAlert = .error(message)
                }
            }
        }
    }
}

private struct AccountCartStatusRow: View {
    let cartTitle: String
    let roleLine: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cart.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
                .frame(width: 36, height: 36)
                .background(
                    OneCartPalette.primarySoft,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(cartTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(roleLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private enum AccountActionStyle {
    case regular
    case destructive
}

private struct AccountActionRow<Trailing: View>: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var style: AccountActionStyle = .regular
    @ViewBuilder var trailing: () -> Trailing

    init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        style: AccountActionStyle = .regular,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.style = style
        self.trailing = trailing
    }

    private var accent: Color {
        style == .destructive ? OneCartPalette.danger : OneCartPalette.primaryAccent
    }

    private var softFill: Color {
        style == .destructive
            ? OneCartPalette.danger.opacity(0.14)
            : OneCartPalette.primarySoft
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(softFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(titleKey)
                .font(.body)
                .foregroundStyle(style == .destructive ? OneCartPalette.danger : .primary)

            Spacer(minLength: 0)

            trailing()
        }
        .contentShape(Rectangle())
    }
}

private struct AccountMemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: member.displayName,
                remoteURL: member.avatarURL,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if member.isCurrentUser {
                        Text("common.you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(OneCartPalette.primaryAccent)
                    }
                }
                Text(
                    member.access.isOwner
                        ? String(localized: "cart.owner_role")
                        : String(localized: "cart.member_role")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
