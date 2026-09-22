import Foundation
import SwiftUI

/// Everything Settings needs from the session; the composition root satisfies `init(session:)` with one object.
typealias AccountSessionServices = AccountManaging & MembershipManaging & SessionStateReading

@MainActor
@Observable
final class AccountViewModel {
    var sharePayload: CartSharePayload?
    var isSharing = false
    var shareAlert: UserAlert?
    var confirmingLeave = false
    var memberToRemove: FamilyMember?
    var confirmingSignOut = false
    var confirmingDeleteAccount = false
    var confirmingRevokeInvite = false
    var isEditingDisplayName = false
    var isEditingCartName = false
    var draftDisplayName = ""
    var draftCartName = ""

    private let state: any SessionStateReading
    private let membership: any MembershipManaging
    private let accountManager: any AccountManaging
    private let shareTimeoutNanoseconds: UInt64
    private var shareGeneration = 0

    init(
        state: any SessionStateReading,
        membership: any MembershipManaging,
        account: any AccountManaging,
        shareTimeoutNanoseconds: UInt64 = 48_000_000_000
    ) {
        self.state = state
        self.membership = membership
        accountManager = account
        self.shareTimeoutNanoseconds = shareTimeoutNanoseconds
    }

    convenience init(session: any AccountSessionServices, shareTimeoutNanoseconds: UInt64 = 48_000_000_000) {
        self.init(
            state: session,
            membership: session,
            account: session,
            shareTimeoutNanoseconds: shareTimeoutNanoseconds
        )
    }

    // MARK: - Session state

    var account: OneCartAccount? {
        state.account
    }

    var hasActiveFamilySpace: Bool {
        state.activeFamilySpace != nil
    }

    var cartTitle: String {
        state.cartTitle
    }

    var isOnline: Bool {
        state.isOnline
    }

    var isBusy: Bool {
        state.isBusy
    }

    var isDeletingAccount: Bool {
        state.isDeletingAccount
    }

    var isFamilyMetadataLoading: Bool {
        state.isFamilyMetadataLoading
    }

    var preferences: DevicePreferences {
        state.preferences
    }

    var needsAccountName: Bool {
        ParticipantDisplayName.isPlaceholder(state.account?.displayName)
    }

    var deleteAccountConfirmMessageKey: LocalizedStringKey {
        if state.access?.isOwner == true, state.familyMembers.contains(where: { !$0.isCurrentUser }) {
            return "account.delete_confirm_message_owner"
        }
        if state.access?.isParticipant == true {
            return "account.delete_confirm_message_member"
        }
        return "account.delete_confirm_message"
    }

    var cartRoleLineKey: LocalizedStringKey {
        if state.access?.isParticipant == true {
            "account.role_member_status"
        } else {
            "account.role_owner_status"
        }
    }

    var cartSectionFooterKey: LocalizedStringKey {
        if state.access?.isParticipant == true {
            "account.cart_status_member_footer"
        } else if state.access?.isOwner == true {
            "account.share_link_warning"
        } else {
            "account.cart_status_owner_footer"
        }
    }

    /// Members from the server, or the signed-in account alone until they arrive.
    var displayedMembers: [FamilyMember] {
        if !state.familyMembers.isEmpty {
            return state.familyMembers
        }
        guard let account = state.account, let family = state.activeFamilySpace else { return [] }
        return [
            FamilyMember(
                id: account.id,
                displayName: account.displayName,
                access: state.access ?? .owner,
                joinedAt: family.createdAt ?? Date(),
                isCurrentUser: true,
                avatarURL: account.avatarURL,
                bannerURL: account.bannerURL
            ),
        ]
    }

    var canOwnerManageMembers: Bool {
        state.access?.isOwner == true
    }

    var canRenameCart: Bool {
        state.access?.isOwner == true
    }

    var canRevokeInvite: Bool {
        state.access?.isOwner == true
    }

    var canLeaveCart: Bool {
        state.access?.isParticipant == true
    }

    /// Any member may forward the invite (REQ-SHARE-110), but only online and one at a time.
    var canShareCart: Bool {
        hasActiveFamilySpace && isOnline && !isSharing
    }

    var appVersion: (version: String, build: String) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return (version, build)
    }

    var cartNamePromptKey: LocalizedStringKey {
        if state.isActiveFamilySpacePrivate {
            "account.cart_name_prompt_personal"
        } else {
            "account.cart_name_prompt"
        }
    }

    // MARK: - Actions

    func refreshAccountSharing() async {
        await membership.refreshAccountSharing()
    }

    func beginEditingDisplayName() {
        let preferred = state.preferences.participantDisplayName
        if preferred.isEmpty {
            let accountName = state.account?.displayName
            draftDisplayName = ParticipantDisplayName.isPlaceholder(accountName) ? "" : (accountName ?? "")
        } else {
            draftDisplayName = preferred
        }
        isEditingDisplayName = true
    }

    func beginEditingCartName() {
        draftCartName = state.activeFamilySpace?.displayName ?? state.cartTitle
        isEditingCartName = true
    }

    func saveDisplayName() async {
        let name = draftDisplayName
        isEditingDisplayName = false
        await accountManager.updateParticipantDisplayName(name)
    }

    func saveCartName() async {
        let name = draftCartName
        isEditingCartName = false
        await membership.renameActiveCart(name)
    }

    func removeMember(_ member: FamilyMember) async {
        await membership.removeMember(member)
    }

    func leaveCurrentFamily() async {
        await membership.leaveCurrentFamily()
    }

    func revokeInviteLink() async {
        await membership.revokeInviteLink()
    }

    func signOut() {
        accountManager.signOut()
    }

    func deleteAccount() async {
        await accountManager.deleteAccount()
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
                let link = try await membership.createFamilyInviteLink()
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
                    shareAlert = .error(membership.userFacingMessage(for: error))
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
