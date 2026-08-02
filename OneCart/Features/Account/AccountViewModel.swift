import Combine
import Foundation

@MainActor
final class AccountViewModel: ObservableObject {
    @Published var sharePayload: CartSharePayload?
    @Published var isSharing = false
    @Published var shareAlert: UserAlert?
    @Published var confirmingLeave = false
    @Published var memberToRemove: FamilyMember?
    @Published var confirmingSignOut = false
    @Published var confirmingRevokeInvite = false
    @Published var isEditingDisplayName = false
    @Published var isEditingCartName = false
    @Published var draftDisplayName = ""
    @Published var draftCartName = ""

    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    var needsAccountName: Bool {
        ParticipantDisplayName.isPlaceholder(session.account?.displayName)
    }

    var cartRoleLine: String {
        if session.access?.isParticipant == true {
            String(localized: "account.role_member_status")
        } else {
            String(localized: "account.role_owner_status")
        }
    }

    var cartSectionFooter: String {
        if session.access?.isParticipant == true {
            String(localized: "account.cart_status_member_footer")
        } else if session.access?.isOwner == true {
            String(localized: "account.share_link_warning")
        } else {
            String(localized: "account.cart_status_owner_footer")
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

    var cartNamePrompt: String {
        if let family = session.activeFamilySpace,
           session.persistence.scope(for: family) == .private
        {
            return String(localized: "account.cart_name_prompt_personal")
        }
        return String(localized: "account.cart_name_prompt")
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

    func shareCart() {
        guard !isSharing else { return }
        isSharing = true
        CartHaptics.light()
        CartSyncLog.action.info("shareCart UI start")
        let work = Task { @MainActor in
            defer { isSharing = false }
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
            try? await Task.sleep(nanoseconds: 48_000_000_000)
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
