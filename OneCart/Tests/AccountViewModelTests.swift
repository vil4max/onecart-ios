import Foundation
@testable import OneCart
import SwiftUI
import Testing
import XCTest

@MainActor
final class AccountViewModelTests: XCTestCase {
    func test_REQ_SHELL_030_ownerGatesEnableRenameAndRevoke() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Owner")
        session.access = .owner

        let viewModel = AccountViewModel(session: session)
        XCTAssertTrue(viewModel.canRenameCart)
        XCTAssertTrue(viewModel.canRevokeInvite)
        XCTAssertTrue(viewModel.canOwnerManageMembers)
        XCTAssertFalse(viewModel.canLeaveCart)
    }

    func test_REQ_SHELL_030_memberGatesEnableLeaveOnly() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        session.account = OneCartAccount(id: UUID(), displayName: "Guest")
        session.access = .member

        let viewModel = AccountViewModel(session: session)
        XCTAssertFalse(viewModel.canRenameCart)
        XCTAssertFalse(viewModel.canRevokeInvite)
        XCTAssertFalse(viewModel.canOwnerManageMembers)
        XCTAssertTrue(viewModel.canLeaveCart)
    }

    func test_REQ_SHARE_030_finishedShareWatchdogDoesNotTimeOutNextShare() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        let viewModel = AccountViewModel(session: session, shareTimeoutNanoseconds: 200_000_000)

        // Without an active family the first share fails immediately.
        viewModel.shareCart()
        for _ in 0 ..< 50 where viewModel.isSharing {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(viewModel.isSharing)
        XCTAssertNotNil(viewModel.shareAlert)

        // Stand in for a second share that is still in flight when the first deadline passes.
        viewModel.shareAlert = nil
        viewModel.isSharing = true
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(viewModel.isSharing)
        XCTAssertNil(viewModel.shareAlert)
    }
}

// MARK: - Fake-backed Settings behaviour

@MainActor
struct AccountHarness {
    let isolated: IsolatedPreferences
    let state: FakeSessionState
    let membership = FakeMembershipManager()
    let accountManager = FakeAccountManager()
    let viewModel: AccountViewModel

    init() throws {
        isolated = try IsolatedPreferences()
        state = FakeSessionState(preferences: isolated.preferences)
        viewModel = AccountViewModel(state: state, membership: membership, account: accountManager)
    }

    /// The share runs on its own task; the fake answers immediately, so a few yields drain it.
    func awaitShareCompletion() async {
        for _ in 0 ..< 1000 where viewModel.isSharing {
            await Task.yield()
        }
    }

    static func member(named name: String, access: FamilyAccess, isCurrentUser: Bool = false) -> FamilyMember {
        FamilyMember(
            id: UUID(),
            displayName: name,
            access: access,
            joinedAt: Date(),
            isCurrentUser: isCurrentUser,
            avatarURL: nil,
            bannerURL: nil
        )
    }
}

@MainActor
@Suite("AccountViewModelFakeTests")
struct AccountViewModelFakeTests {
    @Test("REQ-SHARE-110: sharing hands the session's invite link to the share sheet")
    func shareHandsOutInviteLink() async throws {
        let harness = try AccountHarness()
        let link = try FamilyInviteLink(
            id: UUID(),
            familyName: "Family",
            url: #require(URL(string: "https://example.com/i"))
        )
        harness.membership.inviteLinkResult = .success(link)

        harness.viewModel.shareCart()
        harness.viewModel.shareCart()
        await harness.awaitShareCompletion()

        #expect(harness.membership.createInviteLinkCount == 1)
        #expect(harness.viewModel.sharePayload?.link == link)
        #expect(harness.viewModel.shareAlert == nil)
        #expect(!harness.viewModel.isSharing)
    }

    @Test("REQ-SHELL-050: a failed share shows the session's user-facing message as an alert")
    func failedShareShowsUserFacingAlert() async throws {
        let harness = try AccountHarness()
        harness.membership.userFacingMessage = "No network"

        harness.viewModel.shareCart()
        await harness.awaitShareCompletion()

        #expect(harness.viewModel.sharePayload == nil)
        #expect(harness.viewModel.shareAlert == .error("No network"))
        #expect(harness.membership.describedErrors.count == 1)
    }

    @Test("REQ-SHARE-110: any member may share, but only online, with a cart, one share at a time")
    func shareGateNeedsCartAndNetwork() throws {
        let fixture = try AccountHarness()
        #expect(!fixture.viewModel.canShareCart)

        let store = PersistenceController(inMemory: true, cloudKitEnabled: false)
        fixture.state.activeFamilySpace = FamilySpace(context: store.container.viewContext)
        fixture.state.access = .member
        #expect(fixture.viewModel.canShareCart)

        fixture.state.isOnline = false
        #expect(!fixture.viewModel.canShareCart)

        fixture.state.isOnline = true
        fixture.viewModel.isSharing = true
        #expect(!fixture.viewModel.canShareCart)
    }

    @Test("REQ-CART-110: renaming the cart starts from the current title and forwards the draft")
    func renameCartForwardsDraft() async throws {
        let harness = try AccountHarness()
        harness.state.cartTitle = "Alex's cart"

        harness.viewModel.beginEditingCartName()
        #expect(harness.viewModel.isEditingCartName)
        #expect(harness.viewModel.draftCartName == "Alex's cart")

        harness.viewModel.draftCartName = "Weekend cart"
        await harness.viewModel.saveCartName()

        #expect(!harness.viewModel.isEditingCartName)
        #expect(harness.membership.renamedCartNames == ["Weekend cart"])
    }

    @Test("REQ-CART-100: the cart-name prompt distinguishes a personal cart from a shared one")
    func cartNamePromptFollowsScope() throws {
        let harness = try AccountHarness()
        #expect(harness.viewModel.cartNamePromptKey == "account.cart_name_prompt")

        harness.state.isActiveFamilySpacePrivate = true
        #expect(harness.viewModel.cartNamePromptKey == "account.cart_name_prompt_personal")
    }

    @Test("REQ-AUTH-040: the display-name editor starts from the device name, then the account, never a placeholder")
    func displayNameEditorSeedsFromDeviceThenAccount() async throws {
        let harness = try AccountHarness()
        harness.state.account = OneCartAccount(id: UUID(), displayName: "Alex")

        harness.viewModel.beginEditingDisplayName()
        #expect(harness.viewModel.draftDisplayName == "Alex")
        #expect(harness.viewModel.isEditingDisplayName)
        #expect(!harness.viewModel.needsAccountName)

        harness.state.account = OneCartAccount(id: UUID(), displayName: "User")
        harness.viewModel.beginEditingDisplayName()
        #expect(harness.viewModel.draftDisplayName.isEmpty)
        #expect(harness.viewModel.needsAccountName)

        harness.isolated.preferences.participantDisplayName = "Sam"
        harness.viewModel.beginEditingDisplayName()
        #expect(harness.viewModel.draftDisplayName == "Sam")

        harness.viewModel.draftDisplayName = "Samantha"
        await harness.viewModel.saveDisplayName()
        #expect(!harness.viewModel.isEditingDisplayName)
        #expect(harness.accountManager.updatedDisplayNames == ["Samantha"])
    }

    @Test("REQ-SHARE-040: removing a member forwards that member to the session")
    func removeMemberForwards() async throws {
        let harness = try AccountHarness()
        let guest = AccountHarness.member(named: "Guest", access: .member)

        await harness.viewModel.removeMember(guest)

        #expect(harness.membership.removedMembers == [guest])
    }

    @Test("REQ-SHARE-050: leaving the cart forwards to the session")
    func leaveForwards() async throws {
        let harness = try AccountHarness()
        await harness.viewModel.leaveCurrentFamily()
        #expect(harness.membership.leaveCount == 1)
    }

    @Test("REQ-SHARE-060: revoking the invite forwards to the session")
    func revokeForwards() async throws {
        let harness = try AccountHarness()
        await harness.viewModel.revokeInviteLink()
        #expect(harness.membership.revokeInviteLinkCount == 1)
    }

    @Test("REQ-SHELL-030: the cart section reads the members list from the session")
    func refreshAndMembersMirrorSession() async throws {
        let harness = try AccountHarness()
        let owner = AccountHarness.member(named: "Alex", access: .owner, isCurrentUser: true)
        harness.state.familyMembers = [owner]
        harness.state.isFamilyMetadataLoading = true

        await harness.viewModel.refreshAccountSharing()

        #expect(harness.membership.refreshAccountSharingCount == 1)
        #expect(harness.viewModel.displayedMembers == [owner])
        #expect(harness.viewModel.isFamilyMetadataLoading)
    }

    @Test("REQ-SHELL-030: without a server list the signed-in account stands in as the only member")
    func displayedMembersFallBackToAccount() async throws {
        let fixture = try await CartFixture.make()
        let harness = try AccountHarness()
        #expect(harness.viewModel.displayedMembers.isEmpty)

        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        harness.state.account = account
        harness.state.activeFamilySpace = try fixture.family

        let members = harness.viewModel.displayedMembers
        #expect(members.count == 1)
        #expect(members.first?.id == account.id)
        #expect(members.first?.isCurrentUser == true)
        #expect(members.first?.access == .owner)
    }

    @Test("REQ-AUTH-060: sign out forwards to the session")
    func signOutForwards() throws {
        let harness = try AccountHarness()
        harness.viewModel.signOut()
        #expect(harness.accountManager.signOutCount == 1)
    }

    @Test("REQ-AUTH-070: delete account forwards and its warning depends on the role")
    func deleteAccountForwardsWithRoleWarning() async throws {
        let harness = try AccountHarness()
        #expect(harness.viewModel.deleteAccountConfirmMessageKey == "account.delete_confirm_message")

        harness.state.access = .owner
        harness.state.familyMembers = [
            AccountHarness.member(named: "Alex", access: .owner, isCurrentUser: true),
            AccountHarness.member(named: "Guest", access: .member),
        ]
        #expect(harness.viewModel.deleteAccountConfirmMessageKey == "account.delete_confirm_message_owner")

        harness.state.access = .member
        #expect(harness.viewModel.deleteAccountConfirmMessageKey == "account.delete_confirm_message_member")

        await harness.viewModel.deleteAccount()
        #expect(harness.accountManager.deleteAccountCount == 1)
    }

    @Test("REQ-SHELL-030: role copy follows the access level")
    func roleCopyFollowsAccess() throws {
        let harness = try AccountHarness()
        #expect(harness.viewModel.cartRoleLineKey == "account.role_owner_status")
        #expect(harness.viewModel.cartSectionFooterKey == "account.cart_status_owner_footer")

        harness.state.access = .owner
        #expect(harness.viewModel.cartSectionFooterKey == "account.share_link_warning")

        harness.state.access = .member
        #expect(harness.viewModel.cartRoleLineKey == "account.role_member_status")
        #expect(harness.viewModel.cartSectionFooterKey == "account.cart_status_member_footer")
    }
}
