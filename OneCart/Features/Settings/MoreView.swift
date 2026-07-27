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

    init(model: AppModel) {
        _viewModel = StateObject(wrappedValue: CartShareViewModel(session: model))
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    if model.isFamilyMetadataLoading, displayedMembers.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(OneCartPalette.primary)
                            Text("Обновляем участников…")
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
                                            Label("Удалить", systemImage: "person.fill.xmark")
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
                                Label("Поделиться корзиной", systemImage: "square.and.arrow.up")
                                Spacer()
                                if isSharing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSharing || !model.isOnline)
                    }
                } header: {
                    Text("Участники")
                } footer: {
                    Text(memberCountText(displayedMembers.count))
                }

                if model.access?.isParticipant == true {
                    Section {
                        Button(role: .destructive) {
                            confirmingLeave = true
                        } label: {
                            Label("Покинуть корзину", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } header: {
                    Text("Аккаунт")
                } footer: {
                    if let account = model.account {
                        Text("Вход: \(account.displayName)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Аккаунт")
            .task {
                await model.refreshAccountSharing()
            }
            .sheet(item: $sharePayload) { payload in
                CartActivityViewController(
                    activityItems: [CartInviteActivityItem(link: payload.link)]
                )
            }
            .alert(
                "OneCart",
                isPresented: Binding(
                    get: { shareAlert != nil },
                    set: { if !$0 { shareAlert = nil } }
                )
            ) {
                Button("OK", role: .cancel) { shareAlert = nil }
            } message: {
                Text(shareAlert ?? "")
            }
            .alert("Покинуть корзину?", isPresented: $confirmingLeave) {
                Button("Отмена", role: .cancel) {}
                Button("Покинуть", role: .destructive) {
                    Task { await viewModel.leaveCurrentFamily() }
                }
            } message: {
                Text("Список исчезнет из вашего аккаунта. Данные остальных участников не изменятся.")
            }
            .alert(item: $memberToRemove) { member in
                Alert(
                    title: Text("Удалить участника?"),
                    message: Text("\(member.displayName) потеряет доступ к этой корзине."),
                    primaryButton: .destructive(Text("Удалить")) {
                        Task { await viewModel.removeMember(member) }
                    },
                    secondaryButton: .cancel()
                )
            }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) {
                    model.signOut()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Корзина на этом устройстве останется локально до следующего входа.")
            }
        }
        .navigationViewStyle(.stack)
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

    private func shareCart() {
        guard !isSharing else { return }
        isSharing = true
        let work = Task { @MainActor in
            defer { isSharing = false }
            do {
                let link: FamilyInviteLink
                if let cached = model.preparedInviteLink,
                   cached.expiresAt > Date().addingTimeInterval(30)
                {
                    link = cached
                } else {
                    link = try await model.createFamilyInviteLink()
                }
                guard !Task.isCancelled else { return }
                sharePayload = CartSharePayload(link: link)
            } catch is CancellationError {
                return
            } catch {
                shareAlert = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 24_000_000_000)
            guard !work.isCancelled else { return }
            if isSharing {
                work.cancel()
                isSharing = false
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
                image: nil,
                remoteURL: member.avatarURL,
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.body.weight(.semibold))
                    if member.isCurrentUser {
                        Text("вы")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(OneCartPalette.primaryAccent)
                    }
                }
                Text(member.access.isOwner ? "Владелец корзины" : "Участник корзины")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
