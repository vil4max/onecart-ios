import SwiftUI

struct AccountView: View {
    @Bindable var viewModel: AccountViewModel
    /// Device preferences outlive the screen; the pickers bind straight to them.
    @Bindable private var preferences: DevicePreferences

    init(viewModel: AccountViewModel) {
        self.viewModel = viewModel
        _preferences = Bindable(wrappedValue: viewModel.preferences)
    }

    var body: some View {
        NavigationStack {
            Form {
                cartSection
                if viewModel.hasActiveFamilySpace {
                    sharingSection
                }
                signedInSection
                lookAndFeelSection
                accountSection
                aboutFooter
            }
            .navigationTitle("settings.nav_title")
            .task {
                // Single request path: member-join notifications reuse this grant.
                // Two concurrent requests with different options race on first run.
                CartActivityNotifier.requestAuthorizationIfNeeded()
                await viewModel.refreshAccountSharing()
            }
            .sheet(isPresented: $viewModel.isEditingDisplayName) {
                NameEditorSheet(
                    titleKey: "account.edit_display_name",
                    placeholderKey: "account.display_name_placeholder",
                    promptKey: "account.display_name_prompt",
                    saveKey: "account.display_name_save",
                    text: $viewModel.draftDisplayName,
                    onCancel: { viewModel.isEditingDisplayName = false },
                    onSave: { Task { await viewModel.saveDisplayName() } }
                )
            }
            .sheet(isPresented: $viewModel.isEditingCartName) {
                NameEditorSheet(
                    titleKey: "account.rename_cart",
                    placeholderKey: "account.cart_name_placeholder",
                    promptKey: viewModel.cartNamePromptKey,
                    saveKey: "account.cart_name_save",
                    text: $viewModel.draftCartName,
                    requiresText: true,
                    onCancel: { viewModel.isEditingCartName = false },
                    onSave: { Task { await viewModel.saveCartName() } }
                )
            }
            .sheet(item: $viewModel.sharePayload) { payload in
                CartActivityViewController(activityItems: [CartInviteActivityItem(link: payload.link)])
            }
            .alert(
                viewModel.shareAlert?.kind.title ?? "",
                isPresented: $viewModel.isShowingShareAlert
            ) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(viewModel.shareAlert?.message ?? "")
            }
            .confirmationDialog(
                "account.remove_member_title",
                isPresented: $viewModel.isConfirmingMemberRemoval,
                titleVisibility: .visible,
                presenting: viewModel.memberToRemove
            ) { member in
                Button("account.remove_member_action", role: .destructive) {
                    Task { await viewModel.removeMember(member) }
                }
            } message: { member in
                Text("account.remove_member_message \(member.displayName)")
            }
            .confirmationDialog(
                "account.leave_confirm_title",
                isPresented: $viewModel.confirmingLeave,
                titleVisibility: .visible
            ) {
                Button("account.leave_confirm_action", role: .destructive) {
                    Task { await viewModel.leaveCurrentFamily() }
                }
            } message: {
                Text("account.leave_confirm_message")
            }
            .confirmationDialog(
                "account.revoke_invite_title",
                isPresented: $viewModel.confirmingRevokeInvite,
                titleVisibility: .visible
            ) {
                Button("account.revoke_invite_confirm", role: .destructive) {
                    Task { await viewModel.revokeInviteLink() }
                }
            } message: {
                Text("account.revoke_invite_message")
            }
            .confirmationDialog(
                "account.sign_out_confirm_title",
                isPresented: $viewModel.confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("account.sign_out", role: .destructive) {
                    viewModel.signOut()
                }
            } message: {
                Text("account.sign_out_message")
            }
            .confirmationDialog(
                "account.delete_confirm_title",
                isPresented: $viewModel.confirmingDeleteAccount,
                titleVisibility: .visible
            ) {
                Button("account.delete_confirm_action", role: .destructive) {
                    Task { await viewModel.deleteAccount() }
                }
            } message: {
                Text(viewModel.deleteAccountConfirmMessageKey)
            }
        }
    }

    // MARK: - Sections

    private var cartSection: some View {
        Section {
            if viewModel.hasActiveFamilySpace {
                cartNameRow
            }

            if viewModel.isFamilyMetadataLoading, viewModel.displayedMembers.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("account.updating_members")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.displayedMembers) { member in
                    AccountMemberRow(member: member, accent: preferences.accentColor)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if viewModel.canRemove(member) {
                                Button(role: .destructive) {
                                    viewModel.memberToRemove = member
                                } label: {
                                    Label("account.remove_member_action", systemImage: "person.fill.xmark")
                                }
                            }
                        }
                }
            }

            if viewModel.canLeaveCart {
                Button("account.leave_cart", role: .destructive) {
                    viewModel.confirmingLeave = true
                }
            }
        } header: {
            Text("settings.cart_section")
        } footer: {
            Text(viewModel.cartSectionFooterKey)
        }
    }

    @ViewBuilder
    private var cartNameRow: some View {
        let titleAndRole = VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.cartTitle)
            Text(viewModel.cartRoleLineKey)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if viewModel.canRenameCart {
            Button {
                viewModel.beginEditingCartName()
            } label: {
                LabeledContent {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                } label: {
                    titleAndRole
                }
            }
            .tint(.primary)
            .accessibilityLabel(Text(viewModel.cartTitle))
            .accessibilityHint(Text("account.cart_name_hint"))
        } else {
            titleAndRole
        }
    }

    private var sharingSection: some View {
        Section {
            Button {
                viewModel.shareCart()
            } label: {
                LabeledContent {
                    if viewModel.isSharing {
                        ProgressView()
                    }
                } label: {
                    Label("account.share_cart", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(!viewModel.canShareCart)
            .accessibilityHint(Text("account.share_cart_hint"))

            if viewModel.canRevokeInvite {
                Button {
                    viewModel.confirmingRevokeInvite = true
                } label: {
                    Label("account.revoke_invite", systemImage: "person.badge.minus")
                }
                .disabled(viewModel.isBusy || !viewModel.isOnline)
            }
        } header: {
            Text("account.sharing_section")
        } footer: {
            Text(viewModel.sharingSectionFooterKey)
        }
    }

    private var signedInSection: some View {
        Section {
            if let account = viewModel.account {
                Button {
                    viewModel.beginEditingDisplayName()
                } label: {
                    HStack(spacing: 12) {
                        MemberAvatarView(
                            name: account.displayName,
                            remoteURL: account.avatarURL,
                            accent: preferences.accentColor
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName)
                            Text(viewModel.displayNameCaptionKey)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.primary)
                .accessibilityLabel(Text(account.displayName))
                .accessibilityHint(Text("account.edit_display_name"))
            }

            Button("account.sign_out") {
                viewModel.confirmingSignOut = true
            }
        } header: {
            Text("settings.apple_section")
        } footer: {
            Text("settings.session_footer")
        }
    }

    private var lookAndFeelSection: some View {
        Section("settings.appearance") {
            AccentColorPickerRow(selection: $preferences.accentColor)

            AppIconPickerRow(selection: preferences.appIcon, accent: preferences.accentColor) { option in
                Task { await viewModel.selectAppIcon(option) }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.theme")
                Picker("settings.theme", selection: $preferences.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.localizedTitleKey).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)

            Picker("settings.language", selection: $preferences.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.localizedTitleKey).tag(language)
                }
            }
        }
    }

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.confirmingDeleteAccount = true
            } label: {
                LabeledContent {
                    if viewModel.isDeletingAccount {
                        ProgressView()
                    }
                } label: {
                    Text("account.delete_account")
                }
            }
            .disabled(viewModel.isDeletingAccount || viewModel.isBusy)
        } header: {
            Text("account.section")
        } footer: {
            Text("settings.delete_account_footer")
        }
    }

    private var aboutFooter: some View {
        Section {} footer: {
            VStack(spacing: 2) {
                Text("common.app_name")
                Text("settings.version_build \(viewModel.appVersion.version) \(viewModel.appVersion.build)")
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
    }
}
