import Combine
import Foundation
import SwiftUI

@MainActor
final class AccountViewModel: ObservableObject {
    @Published var sharePayload: CartSharePayload?
    @Published var isSharing = false
    @Published var shareAlert: UserAlert?
    @Published var confirmingLeave = false
    @Published var memberToRemove: FamilyMember?
    @Published var confirmingSignOut = false
    @Published var confirmingDeleteAccount = false
    @Published var confirmingRevokeInvite = false
    @Published var isEditingDisplayName = false
    @Published var isEditingCartName = false
    @Published var draftDisplayName = ""
    @Published var draftCartName = ""

    private let session: AppSession
    private let shareTimeoutNanoseconds: UInt64
    private var shareGeneration = 0

    init(session: AppSession, shareTimeoutNanoseconds: UInt64 = 48_000_000_000) {
        self.session = session
        self.shareTimeoutNanoseconds = shareTimeoutNanoseconds
    }

    var needsAccountName: Bool {
        ParticipantDisplayName.isPlaceholder(session.account?.displayName)
    }

    var deleteAccountConfirmMessageKey: LocalizedStringKey {
        if session.access?.isOwner == true, session.familyMembers.contains(where: { !$0.isCurrentUser }) {
            return "account.delete_confirm_message_owner"
        }
        if session.access?.isParticipant == true {
            return "account.delete_confirm_message_member"
        }
        return "account.delete_confirm_message"
    }

    var cartRoleLineKey: LocalizedStringKey {
        if session.access?.isParticipant == true {
            "account.role_member_status"
        } else {
            "account.role_owner_status"
        }
    }

    var cartSectionFooterKey: LocalizedStringKey {
        if session.access?.isParticipant == true {
            "account.cart_status_member_footer"
        } else if session.access?.isOwner == true {
            "account.share_link_warning"
        } else {
            "account.cart_status_owner_footer"
        }
    }

    var displayedMembers: [FamilyMember] {
        if !session.familyMembers.isEmpty {
            return session.familyMembers
        }
        guard let account = session.account, session.activeFamilySpace != nil else { return [] }
        return [
            FamilyMember(
                id: account.id,
                displayName: account.displayName,
                access: session.access ?? .owner,
                joinedAt: session.activeFamilySpace?.createdAt ?? Date(),
                isCurrentUser: true,
                avatarURL: account.avatarURL,
                bannerURL: account.bannerURL
            ),
        ]
    }

    var canOwnerManageMembers: Bool {
        session.access?.isOwner == true
    }

    var canRenameCart: Bool {
        session.access?.isOwner == true
    }

    var canRevokeInvite: Bool {
        session.access?.isOwner == true
    }

    var canLeaveCart: Bool {
        session.access?.isParticipant == true
    }

    var appVersion: (version: String, build: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return (version, build)
    }

    var cartNamePromptKey: LocalizedStringKey {
        if let family = session.activeFamilySpace,
           session.persistence.scope(for: family) == .private
        {
            return "account.cart_name_prompt_personal"
        }
        return "account.cart_name_prompt"
    }

    func beginEditingDisplayName() {
        draftDisplayName = session.preferences.participantDisplayName.isEmpty
            ? (ParticipantDisplayName.isPlaceholder(session.account?.displayName)
                ? ""
                : (session.account?.displayName ?? ""))
            : session.preferences.participantDisplayName
        isEditingDisplayName = true
    }

    func beginEditingCartName() {
        draftCartName = session.activeFamilySpace?.displayName ?? session.cartTitle
        isEditingCartName = true
    }

    func saveDisplayName() async {
        let name = draftDisplayName
        isEditingDisplayName = false
        await session.updateParticipantDisplayName(name)
    }

    func saveCartName() async {
        let name = draftCartName
        isEditingCartName = false
        await session.renameActiveCart(name)
    }

    func removeMember(_ member: FamilyMember) async {
        await session.removeMember(member)
    }

    func leaveCurrentFamily() async {
        await session.leaveCurrentFamily()
    }

    func revokeInviteLink() async {
        await session.revokeInviteLink()
    }

    func signOut() {
        session.signOut()
    }

    func deleteAccount() async {
        await session.deleteAccount()
    }

    func shareCart() {
        guard !isSharing else { return }
        isSharing = true
        CartHaptics.light()
        CartSyncLog.action.info("shareCart UI start")
        shareGeneration += 1
        let generation = shareGeneration
        let work = Task { @MainActor in
            defer { finishShare(generation: generation) }
            do {
                let link = try await session.createFamilyInviteLink()
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
                    shareAlert = .error(session.userFacingMessage(for: error))
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: shareTimeoutNanoseconds)
            guard generation == shareGeneration else { return }
            work.cancel()
            finishShare(generation: generation)
            CartSyncLog.action.error("shareCart UI timeout")
            if let message = OneCartCloudKitError.shareTimedOut.errorDescription {
                shareAlert = .error(message)
            }
        }
    }

    /// Retires the attempt so its watchdog and a late-finishing cancelled task cannot touch a newer share.
    private func finishShare(generation: Int) {
        guard generation == shareGeneration else { return }
        shareGeneration += 1
        isSharing = false
    }
}
