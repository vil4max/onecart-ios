import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Members and leave-cart management.
struct CartManagementSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CartShareViewModel
    @State private var confirmingLeave = false
    @State private var memberToRemove: FamilyMember?

    init(model: AppModel) {
        _viewModel = StateObject(wrappedValue: CartShareViewModel(session: model))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    membersSection

                    if model.access?.isParticipant == true {
                        Button(role: .destructive) {
                            confirmingLeave = true
                        } label: {
                            Label(
                                "Покинуть корзину",
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
            .navigationTitle(model.cartTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert("Покинуть корзину?", isPresented: $confirmingLeave) {
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
                    message: Text("\(member.displayName) потеряет доступ к этой корзине."),
                    primaryButton: .destructive(Text("Удалить")) {
                        Task { await viewModel.removeMember(member) }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(OneCartPalette.primarySoft)
                    .frame(width: 82, height: 82)
                Image(systemName: "cart.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(OneCartPalette.primaryAccent)
            }

            VStack(spacing: 5) {
                Text(model.cartTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(memberCountText(displayedMembers.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .oneCartCard()
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Участники")
                    .font(.headline)
                Spacer()
                Text("\(displayedMembers.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(OneCartPalette.primaryAccent)
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
                            CartMemberProfileView(member: member)
                        } label: {
                            CartMemberRow(member: member)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if model.access?.isOwner == true, !member.isCurrentUser {
                                Button(role: .destructive) {
                                    memberToRemove = member
                                } label: {
                                    Label("Удалить из корзины", systemImage: "person.fill.xmark")
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
}

struct CartSharePayload: Identifiable {
    let id = UUID()
    let link: FamilyInviteLink
}

struct CartActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

final class CartInviteActivityItem: NSObject, UIActivityItemSource {
    let link: FamilyInviteLink

    init(link: FamilyInviteLink) {
        self.link = link
    }

    func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
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

    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
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

private struct CartMemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: member.displayName,
                image: nil,
                remoteURL: member.avatarURL,
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.subheadline.weight(.semibold))
                    if member.isCurrentUser {
                        Text("вы")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(OneCartPalette.primaryAccent)
                    }
                }
                Text(member.access.isOwner ? "Владелец корзины" : "Участник корзины")
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

private struct CartMemberProfileView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemoval = false
    let member: FamilyMember

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ProfileAvatarView(
                    name: member.displayName,
                    image: member.isCurrentUser ? model.profileAvatar : nil,
                    remoteURL: member.avatarURL,
                    size: 96
                )
                .padding(.top, 24)

                Text(member.displayName)
                    .font(.title2.bold())
                Text(member.access.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.access?.isOwner == true, !member.isCurrentUser {
                    Button(role: .destructive) {
                        confirmingRemoval = true
                    } label: {
                        Label("Удалить из корзины", systemImage: "person.fill.xmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(OneCartPalette.danger)
                            .background(
                                OneCartPalette.danger.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(OneCartPalette.background.ignoresSafeArea())
        .navigationTitle("Участник")
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
            Text("\(member.displayName) потеряет доступ к этой корзине.")
        }
    }
}

func memberCountText(_ count: Int) -> String {
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
