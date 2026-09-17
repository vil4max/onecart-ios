import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class CartAccessTests: XCTestCase {
    func testFamilyAccessAllowsSharedListEditing() {
        XCTAssertTrue(FamilyAccess.owner.canEdit)
        XCTAssertTrue(FamilyAccess.member.canEdit)
        XCTAssertTrue(FamilyAccess.owner.isOwner)
        XCTAssertTrue(FamilyAccess.member.isParticipant)
    }

    func testSelectivePermissionAuthorizerBlocksSharedUpdates() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let allowRepository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await allowRepository.createFamilySpace(
            name: "Test",
            cachedForUserID: UUID(),
            isHouseholdDefault: true
        )
        let listID = try XCTUnwrap(
            allowRepository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let productID = try await allowRepository.addProduct(
            to: listID,
            draft: productDraft(name: "Milk")
        )

        let denyRepository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: DenyAllPermissionAuthorizer()
        )
        do {
            try await denyRepository.togglePurchased(id: productID, participantDisplayName: "Sam")
            XCTFail("expected permission denied")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }

        do {
            try await denyRepository.deleteProduct(id: productID)
            XCTFail("expected permission denied on delete")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }
    }

    func testRevokeInviteKeepsFamilySpaceIdentity() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Old",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(familyID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, familyID)
        await session.revokeInviteLink()
        XCTAssertEqual(session.activeFamilySpace?.id, familyID)
        XCTAssertEqual(
            session.alertMessage,
            String(localized: "account.revoke_invite_done")
        )
        XCTAssertEqual(session.userAlert?.kind, .success)
    }

    func testRenameActiveCartUpdatesFamilySpaceName() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: AppSession.householdCartName(for: account),
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(familyID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        await session.renameActiveCart("Дом")
        XCTAssertEqual(session.activeFamilySpace?.id, familyID)
        XCTAssertEqual(session.account?.displayName, "Alex")
        XCTAssertEqual(session.cartTitle, "Дом")
    }

    func testPersonalCartNameUsesAccountDisplayName() {
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        XCTAssertEqual(
            AppSession.householdCartName(for: account),
            String(localized: "cart.personal_title \("Саша")")
        )
    }

    func testRenamingParticipantUpdatesPersonalCartTitleWhileAutoNamed() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: AppSession.householdCartName(for: account),
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(familyID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(
            session.cartTitle,
            String(localized: "cart.personal_title \("Alex")")
        )

        await session.updateParticipantDisplayName("Папа")

        XCTAssertEqual(session.account?.displayName, "Папа")
        XCTAssertEqual(
            session.cartTitle,
            String(localized: "cart.personal_title \("Папа")")
        )
        XCTAssertEqual(session.activeFamilySpace?.id, familyID)
    }

    func testCustomCartNameStopsFollowingParticipantNickname() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: AppSession.householdCartName(for: account),
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(familyID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)

        await session.renameActiveCart("Дом")
        await session.updateParticipantDisplayName("Папа")

        XCTAssertEqual(session.account?.displayName, "Папа")
        XCTAssertEqual(session.cartTitle, "Дом")
        XCTAssertEqual(session.activeFamilySpace?.id, familyID)
    }

    func testSharedCartVisibleAlongsideOwnPrivateCart() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let ownerID = UUID()
        let memberID = UUID()

        let privateID = try await repository.createFamilySpace(
            name: "Моя",
            cachedForUserID: memberID,
            isHouseholdDefault: true
        )
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Семейная"
            space.createdAt = Date()
            space.updatedAt = Date()
            space.isHouseholdDefault = NSNumber(value: true)
        }

        persistence.container.viewContext.processPendingChanges()

        let memberIDs = try Set(repository.fetchFamilySpaces(for: memberID).compactMap(\.id))
        XCTAssertEqual(memberIDs, [privateID, sharedID])

        let ownerIDs = try repository.fetchFamilySpaces(for: ownerID).compactMap(\.id)
        XCTAssertEqual(ownerIDs, [sharedID])
        XCTAssertFalse(ownerIDs.contains(privateID))
    }

    func testFamilyCacheIsScopedToAuthenticatedUser() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let firstUser = UUID()
        let secondUser = UUID()
        _ = try await repository.createFamilySpace(
            name: "Первая группа",
            cachedForUserID: firstUser,
            serverRole: FamilyAccess.owner.rawValue,
            needsRemoteCreation: true
        )

        XCTAssertEqual(try repository.fetchFamilySpaces(for: firstUser).count, 1)
        XCTAssertTrue(try repository.fetchFamilySpaces(for: secondUser).isEmpty)
    }
}
