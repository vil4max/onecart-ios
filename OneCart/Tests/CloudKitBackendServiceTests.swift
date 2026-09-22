import CloudKit
import CoreData
@testable import OneCart
import Testing

/// Decisions the backend makes before or instead of a CloudKit call. Everything that needs
/// a `CKContainer` (account status, share persistence, zone purge) stays out of unit tests.
@Suite("CloudKitBackendService")
@MainActor
struct CloudKitBackendServiceTests {
    @Test("REQ-SHARE-020: an in-memory store hands out an iCloud preview link without CloudKit")
    func inMemoryInviteLinkIsAnICloudPreview() async throws {
        let fixture = try await CartFixture.make()
        let backend = CloudKitBackendService(persistence: fixture.persistence)

        let link = try await backend.createFamilyInviteLink(
            objectID: fixture.family.objectID,
            displayName: "Семья"
        )

        #expect(link.familyName == "Семья")
        #expect(link.url.scheme == "https")
        #expect(link.url.host == "www.icloud.com")
        #expect(link.shareMessage.contains(link.url.absoluteString))
        #expect(backend.cloudContainerInitializedForTesting == false)
    }

    @Test("REQ-SHARE-010: a cart without a share lists its owner as the only member")
    func unsharedCartListsOwnerOnly() async throws {
        let fixture = try await CartFixture.make()
        let backend = CloudKitBackendService(persistence: fixture.persistence)
        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        let family = try fixture.family

        let members = try backend.familyMembers(for: family, account: account)

        #expect(members.count == 1)
        let owner = try #require(members.first)
        #expect(owner.id == account.id)
        #expect(owner.displayName == "Alex")
        #expect(owner.access == .owner)
        #expect(owner.isCurrentUser)
        #expect(owner.joinedAt == family.createdDate)
    }

    @Test("REQ-SHARE-040: removing a member needs the cart's CKShare; without one nothing is kicked")
    func removeMemberWithoutShareFailsAndKeepsCart() async throws {
        let fixture = try await CartFixture.make()
        let backend = CloudKitBackendService(persistence: fixture.persistence)
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
            try await backend.removeMember(guest, fromFamily: fixture.family.objectID)
        }
        #expect(try fixture.family.deletedAt == nil)
    }

    @Test("REQ-SHARE-070: the ACL heal has nothing to persist for a cart without a share")
    func aclHealWithoutShareChangesNothing() async throws {
        let fixture = try await CartFixture.make()
        let backend = CloudKitBackendService(persistence: fixture.persistence)

        let changed = try await backend.ensureReadWriteACL(objectID: fixture.family.objectID)

        #expect(changed == false)
        #expect(backend.cloudContainerInitializedForTesting == false)
    }

    @Test("REQ-SHARE-060: revoking on an in-memory store returns without a CloudKit call")
    func revokeOnInMemoryStoreIsANoOp() async throws {
        let fixture = try await CartFixture.make()
        let backend = CloudKitBackendService(persistence: fixture.persistence)

        try await backend.revokeInviteLink(objectID: fixture.family.objectID)

        #expect(backend.cloudContainerInitializedForTesting == false)
    }

    @Test("REQ-SHARE-050: leaving on an in-memory store asks the caller to discard local leftovers")
    func leaveOnInMemoryStoreDiscardsLeftovers() async throws {
        let fixture = try await CartFixture.make()
        let backend = CloudKitBackendService(persistence: fixture.persistence)

        let discardLeftovers = try await backend.leaveFamily(objectID: fixture.family.objectID)

        #expect(discardLeftovers)
    }

    @Test("REQ-AUTH-040: the in-memory account keeps a non-blank display name")
    func inMemoryRestoredAccountKeepsDisplayName() async throws {
        let fixture = try await CartFixture.make()
        let backend = CloudKitBackendService(persistence: fixture.persistence)

        let account = try await backend.restoredAccount(appleUserID: "apple-1", displayName: "  Alex  ")

        #expect(account.displayName == "Alex")
        #expect(account.id == OneCartStableID.uuid(for: "onecart.in-memory-user"))
    }

    @Test("REQ-AUTH-030: a local-only store derives the account from the Apple user ID and skips iCloud")
    func localOnlyStoreRestoresAccountWithoutCloudKit() async throws {
        let store = try await LocalOnlyStore.make()
        let backend = CloudKitBackendService(persistence: store.persistence)

        let named = try await backend.restoredAccount(appleUserID: "user-1", displayName: "Alex")
        let unnamed = try await backend.restoredAccount(appleUserID: "user-1", displayName: nil)

        #expect(named.id == OneCartStableID.uuid(for: "apple:user-1"))
        #expect(named.displayName == "Alex")
        #expect(unnamed.id == named.id)
        #expect(unnamed.displayName == String(localized: "common.default_user"))
        #expect(backend.cloudContainerInitializedForTesting == false)
    }

    @Test("REQ-SHARE-040: on a local-only store every share mutation reports the cart as not shared")
    func localOnlyStoreReportsFamilyNotShared() async throws {
        let store = try await LocalOnlyStore.make()
        let backend = CloudKitBackendService(persistence: store.persistence)
        let objectID = store.family.objectID
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
            try await backend.removeMember(guest, fromFamily: objectID)
        }
        await expectCloudKitError(.familyNotShared) {
            try await backend.revokeInviteLink(objectID: objectID)
        }
        await expectCloudKitError(.familyNotShared) {
            _ = try await backend.leaveFamily(objectID: objectID)
        }
        #expect(try await backend.ensureReadWriteACL(objectID: objectID) == false)
        #expect(backend.cloudContainerInitializedForTesting == false)
    }
}

/// A SQLite store in a temporary directory with CloudKit mirroring disabled: the backend
/// then takes its real (non in-memory) branches while `fetchShares` finds no share.
@MainActor
private final class LocalOnlyStore {
    let directory: URL
    let persistence: PersistenceController
    let family: FamilySpace

    private init(directory: URL, persistence: PersistenceController, family: FamilySpace) {
        self.directory = directory
        self.persistence = persistence
        self.family = family
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    static func make() async throws -> LocalOnlyStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartLocalOnly-\(UUID().uuidString)", isDirectory: true)
        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(name: "Family")
        let family = try #require(try repository.fetchFamilySpace(id: familyID))
        return LocalOnlyStore(directory: directory, persistence: persistence, family: family)
    }
}
