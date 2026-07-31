import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var viewModel: CartShareViewModel
    @State private var sharePayload: CartSharePayload?
    @State private var isSharing = false
    @State private var shareAlert: String?
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
                    if model.isFamilyMetadataLoading, displayedMembers.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(OneCartPalette.primary)
                            Text("account.updating_members")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(displayedMembers) { member in
                            if member.isCurrentUser {
                                Button {
                                    beginEditingDisplayName()
                                } label: {
                                    AccountMemberRow(
                                        member: member,
                                        showsEditHint: true,
                                        signedInCaption: model.account.map {
                                            String(localized: "account.signed_in_as \($0.displayName)")
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                AccountMemberRow(member: member, showsEditHint: false)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if model.access?.isOwner == true {
                                            Button(role: .destructive) {
                                                memberToRemove = member
                                            } label: {
                                                Label("common.delete", systemImage: "person.fill.xmark")
                                            }
                                        }
                                    }
                            }
                        }
                    }
                } header: {
                    Text(memberCountText(displayedMembers.count))
                }

                Section {
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

                        AccountInfoRow(
                            systemImage: "link.circle.fill",
                            textKey: model.access?.isOwner == true
                                ? "account.share_link_warning"
                                : "account.share_link_member_hint"
                        )
                    }
                } header: {
                    Text("account.sharing_section")
                }

                Section {
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
                    Text("account.section")
                }
            }
            .listStyle(.insetGrouped)
            .tint(OneCartPalette.primary)
            .navigationTitle("account.nav_title")
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
                            Text("account.cart_name_prompt")
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
                "common.app_name",
                isPresented: Binding(
                    get: { shareAlert != nil },
                    set: { if !$0 { shareAlert = nil } }
                )
            ) {
                Button("common.ok", role: .cancel) { shareAlert = nil }
            } message: {
                Text(shareAlert ?? "")
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

    private func memberCountText(_ count: Int) -> String {
        String(localized: "account.members_count \(count)")
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
                    shareAlert = CloudKitUserFacingError.productionSchemaMissing
                } else {
                    shareAlert = model.userFacingMessage(for: error)
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
                shareAlert = OneCartCloudKitError.shareTimedOut.errorDescription
            }
        }
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

private struct AccountInfoRow: View {
    let systemImage: String
    let textKey: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
                .frame(width: 28, height: 28)
                .background(
                    OneCartPalette.primarySoft,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Text(textKey)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct AccountMemberRow: View {
    let member: FamilyMember
    var showsEditHint: Bool = false
    var signedInCaption: String?

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

                if let signedInCaption, !signedInCaption.isEmpty {
                    Text(signedInCaption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if showsEditHint {
                    Text("account.edit_display_name")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if showsEditHint {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            showsEditHint ? String(localized: "account.edit_display_name") : ""
        )
    }
}
