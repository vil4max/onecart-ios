import CloudKit
import CoreData
@testable import OneCart
import Testing

/// Membership actions on the session (`AppSession+Membership`) over in-memory stores: the
/// gates, the alerts they raise and the state they leave behind. A cart in these stores has
/// no `CKShare`, so the CloudKit kick itself is out of reach; the tests assert what the
/// session does around it.
@Suite("AppSession membership")
@MainActor
struct SessionMembershipTests {

    // MARK: Remove member

    @Test("REQ-SHARE-040: removing a member is a CKShare kick; a cart without a share reports it and stays intact")
    func removeMemberWithoutShareReportsFamilyNotShared() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let guest = fixture.member(named: "Sam")

        await fixture.session.removeMember(guest)

        #expect(fixture.session.userAlert?.kind == .error)
        #expect(fixture.session.alertMessage == String(localized: "sync.family_not_shared"))
        #expect(fixture.session.activeFamilySpace?.id == fixture.personalID)
        #expect(fixture.session.access == .owner)
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-SHARE-040: the owner cannot remove themself")
    func removingTheCurrentUserIsIgnored() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        await fixture.session.refreshFamilyMetadata(showErrors: true)
        let me = try #require(fixture.session.familyMembers.first { $0.isCurrentUser })

        await fixture.session.removeMember(me)

        #expect(fixture.session.userAlert == nil)
        #expect(fixture.session.familyMembers == [me])
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-SHARE-040: removing a member needs the network")
    func removeMemberOfflineShowsNetworkAlert() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        fixture.session.online = false

        await fixture.session.removeMember(fixture.member(named: "Sam"))

        #expect(fixture.session.userAlert?.kind == .error)
        #expect(fixture.session.alertMessage == String(localized: "alert.members_need_network"))
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-SHARE-040: a guest cannot remove members")
    func guestCannotRemoveMembers() async throws {
        let fixture = try await MembershipSessionFixture.guest()
        #expect(fixture.session.access == .member)

        await fixture.session.removeMember(fixture.member(named: "Owner", access: .owner))

        #expect(fixture.session.userAlert == nil)
        #expect(fixture.session.activeFamilySpace?.id == fixture.sharedID)
        #expect(fixture.session.isBusy == false)
    }

    // MARK: Revoke invite

    @Test("REQ-SHARE-060: revoking the invite needs the network")
    func revokeOfflineShowsNetworkAlert() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        fixture.session.online = false

        await fixture.session.revokeInviteLink()

        #expect(fixture.session.userAlert?.kind == .error)
        #expect(fixture.session.alertMessage == String(localized: "alert.revoke_invite_need_network"))
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-SHARE-060: revoking drops the prepared invite link and reports success")
    func revokeClearsPreparedLinkAndReportsSuccess() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let link = try await fixture.session.createFamilyInviteLink()
        #expect(fixture.session.preparedInviteLink == link)

        await fixture.session.revokeInviteLink()

        #expect(fixture.session.preparedInviteLink == nil)
        #expect(fixture.session.userAlert?.kind == .success)
        #expect(fixture.session.alertMessage == String(localized: "account.revoke_invite_done"))
        #expect(fixture.session.activeFamilySpace?.id == fixture.personalID)
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-SHARE-060: revoking is ignored while signed out")
    func revokeWhileSignedOutDoesNothing() async throws {
        let fixture = try await MembershipSessionFixture.signedOut()
        #expect(fixture.session.account == nil)

        await fixture.session.revokeInviteLink()

        #expect(fixture.session.userAlert == nil)
        #expect(fixture.session.isBusy == false)
    }

    // MARK: Rename

    @Test("REQ-CART-110: rename trims the name and ignores a blank one")
    func renameTrimsAndIgnoresBlankName() async throws {
        let fixture = try await MembershipSessionFixture.owner()

        await fixture.session.renameActiveCart("  Дом  ")
        #expect(fixture.session.cartTitle == "Дом")

        await fixture.session.renameActiveCart("   \n")
        #expect(fixture.session.cartTitle == "Дом")
        #expect(fixture.session.userAlert == nil)
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-CART-110: rename drops the prepared invite link so the next share carries the new title")
    func renameClearsPreparedInviteLink() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        _ = try await fixture.session.createFamilyInviteLink()
        #expect(fixture.session.preparedInviteLink != nil)

        await fixture.session.renameActiveCart("Новая")

        #expect(fixture.session.preparedInviteLink == nil)
        #expect(fixture.session.cartTitle == "Новая")
    }

    // MARK: Leave

    @Test("REQ-SHARE-050: the owner has no cart to leave")
    func ownerCannotLeave() async throws {
        let fixture = try await MembershipSessionFixture.owner()

        await fixture.session.leaveCurrentFamily()

        #expect(fixture.session.access == .owner)
        #expect(fixture.session.activeFamilySpace?.id == fixture.personalID)
        #expect(fixture.session.userAlert == nil)
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-SHARE-050: leaving after the shared cart already vanished locally still returns to the personal cart")
    func leaveAfterSharedCartGoneReturnsToPersonal() async throws {
        let fixture = try await MembershipSessionFixture.guest()
        let sharedID = try #require(fixture.sharedID)
        #expect(fixture.session.activeFamilySpace?.id == sharedID)
        try await fixture.repository.archiveFamilySpace(id: sharedID)

        await fixture.session.leaveCurrentFamily()

        #expect(fixture.session.activeFamilySpace?.id == fixture.personalID)
        #expect(fixture.session.access == .owner)
        #expect(fixture.session.lastActiveFamilyWasShared == false)
        #expect(fixture.session.userAlert == nil)
        #expect(fixture.session.isBusy == false)
    }

    // MARK: Family metadata

    @Test("REQ-SHARE-010: refreshing metadata lists the owner alone and remembers the member set")
    func refreshMetadataListsOwnerAndStoresSeenMembers() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex")

        await fixture.session.refreshFamilyMetadata(showErrors: true)

        let members = fixture.session.familyMembers
        #expect(members.count == 1)
        #expect(members.first?.id == fixture.account.id)
        #expect(members.first?.displayName == "Alex")
        #expect(members.first?.access == .owner)
        #expect(members.first?.isCurrentUser == true)
        #expect(fixture.session.isFamilyMetadataLoading == false)
        #expect(fixture.session.userAlert == nil)
        let seenKey = "onecart.seen-member-ids.\(fixture.account.id.uuidString)"
        #expect(fixture.defaults.array(forKey: seenKey) as? [String] == [fixture.account.id.uuidString])
    }

    @Test("Metadata refresh is skipped offline and leaves the member list untouched")
    func refreshMetadataOfflineIsSkipped() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        fixture.session.online = false

        await fixture.session.refreshAccountSharing()

        #expect(fixture.session.familyMembers.isEmpty)
        #expect(fixture.session.isFamilyMetadataLoading == false)
        let seenKey = "onecart.seen-member-ids.\(fixture.account.id.uuidString)"
        #expect(fixture.defaults.array(forKey: seenKey) == nil)
    }

    @Test("Metadata refresh is skipped while signed out")
    func refreshMetadataWhileSignedOutIsSkipped() async throws {
        let fixture = try await MembershipSessionFixture.signedOut()

        await fixture.session.refreshFamilyMetadata(showErrors: true)

        #expect(fixture.session.familyMembers.isEmpty)
        #expect(fixture.session.userAlert == nil)
    }

    @Test("REQ-SHELL-030: family management opens on the settings tab")
    func showFamilyManagementRoutesToAccountTab() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        #expect(fixture.session.preferredMainTab == nil)

        fixture.session.showFamilyManagement()

        #expect(fixture.session.preferredMainTab == .account)
    }

    // MARK: Pending shares

    @Test("REQ-SHARE-090: pending shares are left queued until the store is loaded")
    func acceptPendingSharesBeforeStoreLoadIsANoOp() async throws {
        let fixture = try await MembershipSessionFixture.signedOut(loadStore: false)
        #expect(fixture.persistence.isLoaded == false)

        await fixture.session.acceptPendingCloudKitShares()

        #expect(fixture.session.syncState == .synchronized)
        #expect(fixture.session.isBusy == false)
    }

    @Test("REQ-SHARE-090: an empty share queue does not start a sync")
    func acceptPendingSharesWithEmptyQueueIsANoOp() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        _ = AppDelegate.takePendingShareMetadata()

        await fixture.session.acceptPendingCloudKitShares()

        #expect(fixture.session.syncState == .synchronized)
        #expect(fixture.session.isBusy == false)
        #expect(fixture.session.userAlert == nil)
    }
}
