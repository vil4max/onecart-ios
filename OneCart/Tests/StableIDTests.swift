import CloudKit
import CoreData
@testable import OneCart
import XCTest

final class StableIDTests: XCTestCase {
    func testStableIDIsDeterministic() {
        let first = OneCartStableID.uuid(for: "apple:user-1")
        let second = OneCartStableID.uuid(for: "apple:user-1")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            OneCartStableID.uuid(for: "apple:user-1"),
            OneCartStableID.uuid(for: "apple:user-2")
        )
    }

    func testAddProductIsIdempotentForExactStableID() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(repository: repository, name: "Семья")
        let stableID = UUID()

        let first = try await repository.addProduct(
            to: listID,
            id: stableID,
            draft: productDraft(name: "Яйца")
        )
        let second = try await repository.addProduct(
            to: listID,
            id: stableID,
            draft: productDraft(name: "Яйца другие")
        )

        XCTAssertEqual(first, stableID)
        XCTAssertEqual(second, stableID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedProducts.filter { $0.id == stableID }.count, 1)
        XCTAssertEqual(
            space.sortedProducts.first { $0.id == stableID }?.displayName,
            "Яйца"
        )
    }

    func testDeduplicateStableIDsKeepsNewerProduct() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Семья")
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(space.activeLists.first?.id)
        let stableID = UUID()
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)

        try await persistence.performBackgroundTask { context in
            guard let family = try Self.fetchFamilySpace(id: familyID, in: context),
                  let list = try Self.fetchList(id: listID, in: context)
            else {
                throw RepositoryError.familySpaceNotFound
            }

            let first = ProductEntity(context: context)
            try persistence.assign(first, toSameStoreAs: family, in: context)
            first.id = stableID
            first.name = "Старый"
            first.quantity = NSNumber(value: 1)
            first.unit = ProductUnit.piece.rawValue
            first.category = ProductCategory.other.rawValue
            first.estimatedPrice = NSNumber(value: 10)
            first.note = ""
            first.isPurchased = NSNumber(value: false)
            first.createdAt = older
            first.updatedAt = older
            first.familySpace = family
            first.list = list

            let second = ProductEntity(context: context)
            try persistence.assign(second, toSameStoreAs: family, in: context)
            second.id = stableID
            second.name = "Новый"
            second.quantity = NSNumber(value: 1)
            second.unit = ProductUnit.piece.rawValue
            second.category = ProductCategory.other.rawValue
            second.estimatedPrice = NSNumber(value: 10)
            second.note = ""
            second.isPurchased = NSNumber(value: false)
            second.createdAt = newer
            second.updatedAt = newer
            second.familySpace = family
            second.list = list
        }

        try await repository.deduplicateStableIDs()
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND deletedAt == nil",
            stableID as NSUUID
        )
        let alive = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(alive.count, 1)
        XCTAssertEqual(alive.first?.displayName, "Новый")

        let tombstones = try persistence.container.viewContext.fetch(ProductEntity.fetchRequest())
            .filter { $0.id == stableID && $0.deletedAt != nil }
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.displayName, "Старый")
    }

    private static func fetchFamilySpace(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace? {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND deletedAt == nil",
            id as NSUUID
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func fetchList(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> ShoppingListEntity? {
        let request = ShoppingListEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND deletedAt == nil",
            id as NSUUID
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
