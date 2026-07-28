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
    @State private var confirmingDeleteCart = false

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

                    if model.access?.isOwner == true {
                        Button {
                            shareCart()
                        } label: {
                            HStack {
                                Label("account.share_cart", systemImage: "square.and.arrow.up")
                                Spacer()
                                if isSharing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSharing || !model.isOnline)

                        Button {
                            confirmingDeleteCart = true
                        } label: {
                            Label("account.delete_cart", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(model.isBusy || !model.isOnline)
                    }
                } header: {
                    Text("account.members_section")
                } footer: {
                    Text(accountShareFooter)
                }

                if model.access?.isParticipant == true {
                    Section {
                        Button(role: .destructive) {
                            confirmingLeave = true
                        } label: {
                            Label("account.leave_cart", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("account.sign_out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } header: {
                    Text("account.section")
                } footer: {
                    if let account = model.account {
                        Text("account.signed_in_as \(account.displayName)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("account.nav_title")
            .task {
                await model.refreshAccountSharing()
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
            .alert("account.delete_cart_title", isPresented: $confirmingDeleteCart) {
                Button("common.cancel", role: .cancel) {}
                Button("account.delete_cart_confirm", role: .destructive) {
                    Task { await model.deleteCurrentCartAndStartFresh() }
                }
            } message: {
                Text("account.delete_cart_message")
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

    private var accountShareFooter: String {
        let count = memberCountText(displayedMembers.count)
        if model.access?.isOwner == true {
            return "\(count)\n\(String(localized: "account.share_link_warning"))"
        }
        return count
    }

    private func memberCountText(_ count: Int) -> String {
        String(localized: "account.members_count \(count)")
    }

    private func shareCart() {
        guard !isSharing else { return }
        isSharing = true
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

private struct AccountMemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: member.displayName,
                remoteURL: member.avatarURL,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.body.weight(.semibold))
                    if member.isCurrentUser {
                        Text("common.you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(OneCartPalette.primaryAccent)
                    }
                }
                Text(member.access
                    .isOwner ? String(localized: "cart.owner_role") : String(localized: "cart.member_role"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
