import CoreData
import Foundation
@testable import OneCart
import SwiftUI
import Testing
import UIKit

/// Settings over the membership and account fakes, per role.
@MainActor
struct HostedAccountHarness {
    let fixture: CartFixture
    let isolated: IsolatedPreferences
    let state: FakeSessionState
    let membership = FakeMembershipManager()
    let accountManager = FakeAccountManager()
    let iconSwitcher = FakeAppIconSwitcher()
    let account = OneCartAccount(id: UUID(), displayName: "Alex")
    let viewModel: AccountViewModel

    init(access: FamilyAccess) async throws {
        fixture = try await CartFixture.make()
        isolated = try IsolatedPreferences()
        state = FakeSessionState(preferences: isolated.preferences)
        state.account = account
        state.activeFamilySpace = try fixture.family
        state.access = access
        state.cartTitle = "Family"
        viewModel = AccountViewModel(
            state: state,
            membership: membership,
            account: accountManager,
            iconSwitcher: iconSwitcher
        )
    }

    func member(named name: String, access: FamilyAccess = .member, isCurrentUser: Bool = false) -> FamilyMember {
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

/// Settings hosted over fakes: the one-screen layout per role (REQ-SHELL-030), share as a
/// secondary action that lives only here (REQ-SHELL-040, REQ-SHARE-110) and the branding footer.
@MainActor
@Suite("HostedAccountViewTests")
struct HostedAccountViewTests {
    @Test(
        "REQ-SHELL-030: the owner's Settings is one screen: cart, sharing, Apple account, appearance, deletion, about"
    )
    func ownerSettingsListsEverySection() async throws {
        let harness = try await HostedAccountHarness(access: .owner)
        // Tall enough for the whole Form: scrolled-away cells are recycled out of the tree.
        let hosted = HostedView(
            AccountView(viewModel: harness.viewModel),
            size: CGSize(width: HostedView.phoneSize.width, height: 2000)
        )
        defer { hosted.tearDown() }
        #expect(hosted.uiLabelTexts.contains(String(localized: "settings.nav_title")))
        let cartName = try #require(hosted.element(identifier: "account.cart_name"))
        #expect(cartName.label == "Family")
        #expect(cartName.isButton)
        let members = hosted.elements(identifier: "account.member_row")
        #expect(members.count == 1)
        #expect(members.first?.label?.contains("Alex") == true)
        #expect(members.first?.label?.contains(String(localized: "cart.owner_role")) == true)
        #expect(hosted.element(identifier: "account.leave_cart") == nil)

        #expect(hosted.element(identifier: "account.share_cart")?.label == String(localized: "account.share_cart"))
        #expect(hosted.element(identifier: "account.revoke_invite")?
            .label == String(localized: "account.revoke_invite"))

        #expect(hosted.element(identifier: "account.display_name")?.label == "Alex")
        #expect(hosted.element(identifier: "account.sign_out")?.label == String(localized: "account.sign_out"))
        #expect(hosted.containsLabel(String(localized: "settings.accent_color")))
        // The swatches sit in a horizontal scroll view that joins the tree a layout pass later.
        #expect(await hosted.pump {
            AppAccentColor.allCases.allSatisfy { hosted.element(label: $0.title) != nil }
        })
        for color in AppAccentColor.allCases {
            let swatch = try #require(hosted.element(label: color.title))
            #expect(swatch.isSelected == (color == harness.isolated.preferences.accentColor))
        }
        let deleteAccount = try #require(hosted.element(label: String(localized: "account.delete_account")))
        withKnownIssue("A Button with a LabeledContent label reaches the tree as static text while idle") {
            #expect(deleteAccount.isButton)
        }
        // REQ-SHELL-060: the about footer carries the user-facing name.
        #expect(hosted.element(identifier: "account.app_name")?.label == "OneCart Family")
        #expect(hosted.element(identifier: "account.version")?.label?
            .contains(harness.viewModel.appVersion.version) == true)
        #expect(await hosted.pump { harness.membership.refreshAccountSharingCount == 1 })
        // REQ-HIST-050: Settings has no History control either.
        #expect(!hosted.buttons
            .contains { $0.label?.localizedCaseInsensitiveContains(String(localized: "history.nav_title")) == true })
    }

    @Test("REQ-SHELL-030: a member's Settings offers Leave, keeps Share, and hides Rename and Revoke")
    func memberSettingsShowsLeaveNotRevoke() async throws {
        let harness = try await HostedAccountHarness(access: .member)
        let hosted = HostedView(AccountView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }

        #expect(hosted.element(identifier: "account.leave_cart")?.label == String(localized: "account.leave_cart"))
        #expect(hosted.element(identifier: "account.revoke_invite") == nil)
        let cartName = try #require(hosted.element(identifier: "account.cart_name"))
        #expect(!cartName.isButton)
        #expect(cartName.label?.contains("Family") == true)
        #expect(cartName.label?.contains(String(localized: "account.role_member_status")) == true)
        // REQ-SHARE-110: any member can forward the invite.
        #expect(hosted.element(identifier: "account.share_cart")?.isEnabled == true)
        #expect(hosted.containsLabel(String(localized: "account.share_link_member_hint")))
    }

    @Test("REQ-SHELL-040: Share is a secondary Settings action: it creates the invite link and waits for connectivity")
    func shareIsSecondaryActionInSettings() async throws {
        let harness = try await HostedAccountHarness(access: .owner)
        let hosted = HostedView(AccountView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        let share = try #require(hosted.element(identifier: "account.share_cart"))
        #expect(share.isButton)
        #expect(share.isEnabled)
        // Secondary placement: the button sits after the cart section, not first on the screen.
        let cartNameIndex = try #require(hosted.identifiers.firstIndex(of: "account.cart_name"))
        let shareIndex = try #require(hosted.identifiers.firstIndex(of: "account.share_cart"))
        #expect(cartNameIndex < shareIndex)

        #expect(share.activate())
        #expect(await hosted.pump { harness.membership.createInviteLinkCount == 1 })
        #expect(await hosted.pump { !harness.viewModel.isSharing })
        #expect(harness.viewModel.shareAlert != nil)
        #expect(harness.membership.describedErrors.count == 1)

        harness.state.isOnline = false
        #expect(await hosted.pump { hosted.element(identifier: "account.share_cart")?.isEnabled == false })
    }

    @Test("REQ-SHELL-030: the member list follows the session and the loading row covers the gap")
    func memberListFollowsSession() async throws {
        let harness = try await HostedAccountHarness(access: .owner)
        let hosted = HostedView(AccountView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }

        harness.state.familyMembers = [
            harness.member(named: "Alex", access: .owner, isCurrentUser: true),
            harness.member(named: "Sam"),
        ]
        #expect(await hosted.pump { hosted.elements(identifier: "account.member_row").count == 2 })
        let rows = hosted.elements(identifier: "account.member_row")
        #expect(rows.first?.label?.contains(String(localized: "common.you")) == true)
        #expect(rows.last?.label?.contains("Sam") == true)
        #expect(rows.last?.label?.contains(String(localized: "cart.member_role")) == true)

        // Without members from the server the signed-in account stands in; with no account
        // either, the loading row covers the gap.
        harness.state.familyMembers = []
        harness.state.account = nil
        harness.state.isFamilyMetadataLoading = true
        #expect(await hosted.pump { hosted.containsLabel(String(localized: "account.updating_members")) })
    }

    @Test("REQ-SHELL-030: Settings re-renders on ViewModel and preference changes")
    func stateChangesReRender() async throws {
        let harness = try await HostedAccountHarness(access: .owner)
        let hosted = HostedView(AccountView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }

        harness.viewModel.isSharing = true
        #expect(await hosted.pump { hosted.element(identifier: "account.share_cart")?.isEnabled == false })
        harness.viewModel.isSharing = false
        #expect(await hosted.pump { hosted.element(identifier: "account.share_cart")?.isEnabled == true })

        harness.state.isDeletingAccount = true
        #expect(await hosted.pump {
            hosted.scrollToBottom()
            return hosted.element(identifier: "account.delete_account")?.isEnabled == false
        })

        let next = try #require(AppAccentColor.allCases.first { $0 != harness.isolated.preferences.accentColor })
        harness.isolated.preferences.accentColor = next
        #expect(await hosted.pump { hosted.element(label: next.title)?.isSelected == true })
    }
}
