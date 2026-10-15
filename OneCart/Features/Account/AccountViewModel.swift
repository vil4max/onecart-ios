import Foundation
import SwiftUI

/// Everything Settings needs from the session; the composition root satisfies `init(session:)` with one object.
typealias AccountSessionServices = AccountManaging & MembershipManaging & SessionStateReading

@MainActor
@Observable
final class AccountViewModel {
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
    private let iconSwitcher: any AppIconSwitching
    private let clock: AppClock
    private let requestNotificationAuthorization: @MainActor () -> Void
    /// The invite share with its timeout; Settings forwards to it.
    let inviteShare: InviteShareController
    let appVersion: AppVersionInfo

    static let defaultShareTimeout = InviteShareController.defaultTimeout

    init(
        state: any SessionStateReading,
        membership: any MembershipManaging,
        account: any AccountManaging,
        iconSwitcher: any AppIconSwitching = SystemAppIconSwitcher(),
        haptics: any HapticsPlaying = SystemHaptics(),
        appVersion: AppVersionInfo = .unknown,
        shareTimeout: Duration = defaultShareTimeout,
        clock: AppClock = .live,
        requestNotificationAuthorization: @escaping @MainActor () -> Void = {
            CartActivityNotifier.requestAuthorizationIfNeeded()
        }
    ) {
        self.state = state
        self.membership = membership
        accountManager = account
        self.iconSwitcher = iconSwitcher
        self.appVersion = appVersion
        self.clock = clock
        self.requestNotificationAuthorization = requestNotificationAuthorization
        inviteShare = InviteShareController(
            membership: membership,
            haptics: haptics,
            clock: clock,
            timeout: shareTimeout
        )
    }

    convenience init(
        session: any AccountSessionServices,
        appVersion: AppVersionInfo = .unknown,
        shareTimeout: Duration = defaultShareTimeout,
        clock: AppClock = .live
    ) {
        self.init(
            state: session,
            membership: session,
            account: session,
            appVersion: appVersion,
            shareTimeout: shareTimeout,
            clock: clock
        )
    }

    // MARK: - Invite share

    var sharePayload: CartSharePayload? {
        get { inviteShare.sharePayload }
        set { inviteShare.sharePayload = newValue }
    }

    var isSharing: Bool {
        get { inviteShare.isSharing }
        set { inviteShare.isSharing = newValue }
    }

    var shareAlert: UserAlert? {
        get { inviteShare.alert }
        set { inviteShare.alert = newValue }
    }

    func shareCart() {
        inviteShare.share()
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

    var displayNameCaptionKey: LocalizedStringKey {
        needsAccountName ? "settings.apple_set_name" : "settings.apple_edit_name"
    }

    /// Presentation flags for the member-removal dialog and the share alert, bindable from the view.
    var isConfirmingMemberRemoval: Bool {
        get { memberToRemove != nil }
        set {
            if !newValue {
                memberToRemove = nil
            }
        }
    }

    var isShowingShareAlert: Bool {
        get { shareAlert != nil }
        set {
            if !newValue {
                shareAlert = nil
            }
        }
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

    /// The invite-door explanation under the cart section (REQ-SHARE-060, REQ-SHARE-110).
    var sharingSectionFooterKey: LocalizedStringKey {
        if state.access?.isOwner == true {
            "account.share_link_warning"
        } else {
            "account.share_link_member_hint"
        }
    }

    /// Members from the server, or the signed-in account alone until they arrive.
    var displayedMembers: [FamilyMember] {
        if !state.familyMembers.isEmpty {
            return state.familyMembers
        }
        guard let account = state.account, let family = state.activeFamilySpace else { return [] }
        let currentUser = FamilyMember(
            id: account.id,
            displayName: account.displayName,
            access: state.access ?? .owner,
            joinedAt: family.createdAt ?? clock.now(),
            isCurrentUser: true,
            avatarURL: account.avatarURL,
            bannerURL: account.bannerURL
        )
        return [currentUser]
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

    /// Only the owner removes members, and never themselves (REQ-SHARE-040).
    func canRemove(_ member: FamilyMember) -> Bool {
        canOwnerManageMembers && !member.isCurrentUser
    }

    /// Any member may forward the invite (REQ-SHARE-110), but only online and one at a time.
    var canShareCart: Bool {
        hasActiveFamilySpace && isOnline && !isSharing
    }

    var cartNamePromptKey: LocalizedStringKey {
        if state.isActiveFamilySpacePrivate {
            "account.cart_name_prompt_personal"
        } else {
            "account.cart_name_prompt"
        }
    }

    // MARK: - Actions

    /// Settings is the single place that asks for notification permission: member-join and
    /// activity notifications reuse this grant, and two concurrent requests with different
    /// options race on first run.
    func onAppear() async {
        requestNotificationAuthorization()
        await refreshAccountSharing()
    }

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

    /// Persists the choice before asking the system, so the picker reflects it even if the switch is declined.
    func selectAppIcon(_ option: AppIconOption) async {
        guard state.preferences.appIcon != option else { return }
        state.preferences.appIcon = option
        state.preferences.accentColor = option.accent
        await iconSwitcher.setAlternateIcon(to: option)
    }

    func deleteAccount() async {
        await accountManager.deleteAccount()
    }

}

/// The marketing version and build shown in the Settings footer, read once by the composition
/// root so the screen model never reaches `Bundle.main`.
struct AppVersionInfo: Equatable, Sendable {
    let version: String
    let build: String

    static let unknown = AppVersionInfo(version: "—", build: "—")

    init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
