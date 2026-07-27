import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class FamilyCartLifecycleTests: XCTestCase {
    func testClaimUnassignedFamilySpacesStampsPrivateOnly() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let privateID = try await repository.createFamilySpace(name: "Личная")
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Общая"
            space.createdAt = Date()
            space.updatedAt = Date()
        }

        let userID = UUID()
        try await repository.claimUnassignedFamilySpaces(for: userID)

        let privateSpace = try XCTUnwrap(repository.fetchFamilySpace(id: privateID))
        XCTAssertEqual(privateSpace.cachedForUserID, userID)
        XCTAssertEqual(privateSpace.serverRole, "owner")

        let sharedRequest = FamilySpace.fetchRequest()
        sharedRequest.predicate = NSPredicate(format: "id == %@", sharedID as NSUUID)
        let shared = try XCTUnwrap(
            persistence.container.viewContext.fetch(sharedRequest).first
        )
        XCTAssertNil(shared.cachedForUserID)
    }

    func testArchiveFamilySpaceHidesCartAndSoftDeletesChildren() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, _, productID) = try await seedCart(repository: repository)
        _ = try await repository.addStore(
            to: familyID,
            draft: StoreDraft(
                name: "АТБ",
                icon: "АТБ",
                colorHex: "#E30613",
                address: nil,
                externalAppURL: nil,
                isPinned: false
            )
        )

        try await repository.archiveFamilySpace(id: familyID)

        XCTAssertNil(try repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(try repository.fetchFamilySpaces().isEmpty)

        let productRequest = ProductEntity.fetchRequest()
        productRequest.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let product = try XCTUnwrap(
            persistence.container.viewContext.fetch(productRequest).first
        )
        XCTAssertNotNil(product.deletedAt)

        let spaceRequest = FamilySpace.fetchRequest()
        spaceRequest.predicate = NSPredicate(format: "id == %@", familyID as NSUUID)
        let space = try XCTUnwrap(persistence.container.viewContext.fetch(spaceRequest).first)
        XCTAssertNotNil(space.deletedAt)
        let stores = space.stores?.allObjects as? [StoreEntity] ?? []
        XCTAssertTrue(stores.allSatisfy { $0.deletedAt != nil })
    }

    func testRenameFamilySpaceUpdatesDisplayName() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Старое")
        try await repository.renameFamilySpace(id: familyID, name: "  Новое имя  ")
        XCTAssertEqual(
            try repository.fetchFamilySpace(id: familyID)?.displayName,
            "Новое имя"
        )
    }

    func testAssociateAndRemoveCachedFamilySpace() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let userID = UUID()
        let familyID = try await repository.createFamilySpace(name: "Кэш")

        try await repository.associateFamilySpace(
            id: familyID,
            with: userID,
            role: FamilyAccess.owner.rawValue,
            needsRemoteCreation: true
        )
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.cachedForUserID, userID)
        XCTAssertEqual(space.serverRole, FamilyAccess.owner.rawValue)
        XCTAssertEqual(space.needsRemoteCreation?.boolValue, true)

        try await repository.removeCachedFamilySpace(id: familyID, for: userID)
        XCTAssertNil(try repository.fetchFamilySpace(id: familyID))
    }

    func testSoftDeleteStoreUnlinksProducts() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, productID) = try await seedCart(repository: repository)
        let storeID = try await repository.addStore(
            to: familyID,
            draft: StoreDraft(
                name: "АТБ",
                icon: "АТБ",
                colorHex: "#E30613",
                address: nil,
                externalAppURL: nil,
                isPinned: false
            )
        )
        try await assignStore(
            persistence: persistence,
            productID: productID,
            storeID: storeID
        )
        XCTAssertEqual(fetchProduct(id: productID, repository: repository)?.store?.id, storeID)

        try await repository.deleteStore(id: storeID)

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertNil(product.store)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedStores.isEmpty)
        _ = listID
    }
}
