import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class CartAccessTests: XCTestCase {
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

        persistence.container.viewContext.processPendingChanges()

        let memberIDs = Set(try repository.fetchFamilySpaces(for: memberID).compactMap(\.id))
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
