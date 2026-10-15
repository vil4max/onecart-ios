import CoreData
import Foundation
@testable import OneCart
import Testing

/// The contract of the iCloud stand-in the session suites and the DEBUG welcome demo run on. It
/// pins what the production backend used to answer on an ephemeral store, so moving that
/// behavior out of `CloudKitBackendService` changed nothing the session sees.
@Suite("InMemoryFamilySharing", .removesStores)
@MainActor
struct InMemoryFamilySharingTests {
    @Test("REQ-SHARE-020: the invite link is an iCloud preview link that carries the cart name")
    func inviteLinkIsAnICloudPreview() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = InMemoryFamilySharing(persistence: fixture.persistence)

        let link = try await cloudSharing.createFamilyInviteLink(
            objectID: fixture.family.objectID,
            displayName: "Семья"
        )

        #expect(link.familyName == "Семья")
        #expect(link.url.scheme == "https")
        #expect(link.url.host == "www.icloud.com")
        #expect(link.shareMessage.contains(link.url.absoluteString))
    }

    @Test("REQ-AUTH-040: the account is one fixed user with a non-blank display name")
    func restoredAccountKeepsDisplayName() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = InMemoryFamilySharing(persistence: fixture.persistence)

        let named = try await cloudSharing.restoredAccount(appleUserID: "apple-1", displayName: "  Alex  ")
        let blank = try await cloudSharing.restoredAccount(appleUserID: "apple-2", displayName: "  ")

        #expect(named.displayName == "Alex")
        #expect(named.id == OneCartStableID.uuid(for: "onecart.in-memory-user"))
        #expect(blank.id == named.id)
        #expect(blank.displayName == String(localized: "common.default_user"))
    }

    @Test("REQ-SHARE-060: revoking succeeds without a server")
    func revokeIsANoOp() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = InMemoryFamilySharing(persistence: fixture.persistence)

        try await cloudSharing.revokeInviteLink(objectID: fixture.family.objectID)

        #expect(try fixture.family.deletedAt == nil)
    }

    @Test("REQ-SHARE-050: leaving asks the caller to discard local leftovers")
    func leaveDiscardsLeftovers() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = InMemoryFamilySharing(persistence: fixture.persistence)

        let discardLeftovers = try await cloudSharing.leaveFamily(objectID: fixture.family.objectID)

        #expect(discardLeftovers)
    }

    @Test("REQ-SHARE-040: a cart has no CKShare, so removing a member reports it as not shared")
    func removeMemberReportsFamilyNotShared() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = InMemoryFamilySharing(persistence: fixture.persistence)
        let guest = FamilyMember(
            id: UUID(),
            displayName: "Sam",
            access: .member,
            joinedAt: Date(),
            isCurrentUser: false,
            avatarURL: nil,
            bannerURL: nil
        )

        await expectCloudKitError(.familyNotShared) {
            try await cloudSharing.removeMember(guest, fromFamily: fixture.family.objectID)
        }
        #expect(try await cloudSharing.ensureReadWriteACL(objectID: fixture.family.objectID) == false)
    }

    @Test("REQ-SHARE-010: the current user is the only member, with access from the store scope")
    func membersAreTheCurrentUserOnly() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = InMemoryFamilySharing(persistence: fixture.persistence)
        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        let family = try fixture.family

        let members = try cloudSharing.familyMembers(for: family, account: account, currentUserRecordName: "_alex")

        #expect(cloudSharing.access(for: family) == .owner)
        #expect(members.count == 1)
        let owner = try #require(members.first)
        #expect(owner.id == account.id)
        #expect(owner.access == .owner)
        #expect(owner.isCurrentUser)
        #expect(owner.joinedAt == family.createdDate)
    }

    @Test("REQ-AUTH-040: there is no iCloud user to name, and forgetting the identity moves its generation")
    func identityIsUnknownAndResettable() async throws {
        let fixture = try await CartFixture.make()
        let cloudSharing = InMemoryFamilySharing(persistence: fixture.persistence)
        let generation = cloudSharing.identityGeneration

        #expect(await cloudSharing.currentUserRecordName() == nil)
        cloudSharing.resetCachedUserRecordName()

        #expect(cloudSharing.identityGeneration != generation)
        try await cloudSharing.deletePrivateAccountCloudData()
    }
}
