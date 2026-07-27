import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class CartAccessTests: XCTestCase {
    func testRepositoryEnforcesReadOnlyPermission() async throws {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let ownerRepository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await ownerRepository.createFamilySpace(name: "Family")
        let readOnlyRepository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: DenyAllPermissionAuthorizer()
        )

        do {
            _ = try await readOnlyRepository.addStore(
                to: familyID,
                draft: StoreDraft(
                    name: "Store",
                    icon: "S",
                    colorHex: "#34785B",
                    address: nil,
                    externalAppURL: nil,
                    isPinned: false
                )
            )
            XCTFail("Expected permission error")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }
    }

    func testFamilyAccessAllowsSharedListEditing() {
        XCTAssertTrue(FamilyAccess.owner.canEdit)
        XCTAssertTrue(FamilyAccess.member.canEdit)
        XCTAssertTrue(FamilyAccess.owner.isOwner)
        XCTAssertTrue(FamilyAccess.member.isParticipant)
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

        let visibleToMember = try repository.fetchFamilySpaces(for: memberID)
        XCTAssertEqual(Set(visibleToMember.compactMap(\.id)), [privateID, sharedID])

        let visibleToOwner = try repository.fetchFamilySpaces(for: ownerID)
        XCTAssertEqual(visibleToOwner.compactMap(\.id), [sharedID])
        XCTAssertFalse(visibleToOwner.contains { $0.id == privateID })
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
