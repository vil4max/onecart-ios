import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var model: AppSession
    @StateObject private var viewModel: AccountViewModel

    init(model: AppSession) {
        _viewModel = StateObject(wrappedValue: AccountViewModel(session: model))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.isFamilyMetadataLoading, viewModel.displayedMembers.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(OneCartPalette.primary)
                            Text("account.updating_members")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(viewModel.displayedMembers) { member in
                            AccountMemberRow(member: member)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if viewModel.canOwnerManageMembers, !member.isCurrentUser {
                                        Button(role: .destructive) {
                                            viewModel.memberToRemove = member
                                        } label: {
                                            Label("common.delete", systemImage: "person.fill.xmark")
                                        }
                                    }
                                }
                        }
                    }

                    if model.activeFamilySpace != nil {
                        Button {
                            viewModel.shareCart()
                        } label: {
                            AccountActionRow(
                                titleKey: "account.share_cart",
                                systemImage: "square.and.arrow.up",
                                trailing: {
                                    if viewModel.isSharing {
                                        ProgressView()
                                            .tint(OneCartPalette.primary)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSharing || !model.isOnline)

                        if viewModel.canRenameCart {
                            Button {
                                viewModel.beginEditingCartName()
                            } label: {
                                AccountActionRow(
                                    titleKey: "account.rename_cart",
                                    systemImage: "pencil"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.canRevokeInvite {
                            Button {
                                viewModel.confirmingRevokeInvite = true
                            } label: {
                                AccountActionRow(
                                    titleKey: "account.revoke_invite",
                                    systemImage: "person.badge.minus"
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isBusy || !model.isOnline)
                        }

                        if viewModel.canLeaveCart {
                            Button {
                                viewModel.confirmingLeave = true
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
                    if model.activeFamilySpace != nil {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.cartTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                            Text(viewModel.cartRoleLine)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    } else {
                        Text("settings.cart_section")
                    }
                } footer: {
                    Text(viewModel.cartSectionFooter)
                }

                Section {
                    if let account = model.account {
                        Button {
                            viewModel.beginEditingDisplayName()
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
                                        viewModel.needsAccountName
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
                        viewModel.confirmingSignOut = true
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

                Section {} footer: {
                    Text(viewModel.appVersionFooter)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .sheet(isPresented: $viewModel.isEditingDisplayName) {
                NavigationStack {
                    Form {
                        Section {
                            TextField(
                                String(localized: "account.display_name_placeholder"),
                                text: $viewModel.draftDisplayName
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
                            Button("common.cancel") { viewModel.isEditingDisplayName = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("account.display_name_save") {
                                Task { await viewModel.saveDisplayName() }
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $viewModel.isEditingCartName) {
                NavigationStack {
                    Form {
                        Section {
                            TextField(
                                String(localized: "account.cart_name_placeholder"),
                                text: $viewModel.draftCartName
                            )
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        } footer: {
                            Text(viewModel.cartNamePrompt)
                        }
                    }
                    .navigationTitle("account.rename_cart")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.cancel") { viewModel.isEditingCartName = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("account.cart_name_save") {
                                Task { await viewModel.saveCartName() }
                            }
                            .disabled(
                                viewModel.draftCartName
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                            )
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $viewModel.sharePayload) { payload in
                CartActivityViewController(
                    activityItems: [CartInviteActivityItem(link: payload.link)]
                )
            }
            .alert(
                viewModel.shareAlert?.kind.title ?? "",
                isPresented: Binding(
                    get: { viewModel.shareAlert != nil },
                    set: {
                        if !$0 {
                            viewModel.shareAlert = nil
                        }
                    }
                )
            ) {
                Button("common.ok", role: .cancel) { viewModel.shareAlert = nil }
            } message: {
                Text(viewModel.shareAlert?.message ?? "")
            }
            .alert("account.leave_confirm_title", isPresented: $viewModel.confirmingLeave) {
                Button("common.cancel", role: .cancel) {}
                Button("account.leave_confirm_action", role: .destructive) {
                    Task { await viewModel.leaveCurrentFamily() }
                }
            } message: {
                Text("account.leave_confirm_message")
            }
            .alert("account.revoke_invite_title", isPresented: $viewModel.confirmingRevokeInvite) {
                Button("common.cancel", role: .cancel) {}
                Button("account.revoke_invite_confirm", role: .destructive) {
                    Task { await viewModel.revokeInviteLink() }
                }
            } message: {
                Text("account.revoke_invite_message")
            }
            .alert(
                "account.remove_member_title",
                isPresented: Binding(
                    get: { viewModel.memberToRemove != nil },
                    set: {
                        if !$0 {
                            viewModel.memberToRemove = nil
                        }
                    }
                ),
                presenting: viewModel.memberToRemove
            ) { member in
                Button("common.delete", role: .destructive) {
                    Task { await viewModel.removeMember(member) }
                }
                Button("common.cancel", role: .cancel) {}
            } message: { member in
                Text("account.remove_member_message \(member.displayName)")
            }
            .alert("account.sign_out_confirm_title", isPresented: $viewModel.confirmingSignOut) {
                Button("common.cancel", role: .cancel) {}
                Button("account.sign_out", role: .destructive) {
                    viewModel.signOut()
                }
            } message: {
                Text("account.sign_out_message")
            }
        }
    }
}
