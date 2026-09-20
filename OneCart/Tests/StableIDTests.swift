import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
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

    private nonisolated static func fetchFamilySpace(
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

    private nonisolated static func fetchList(
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

@MainActor
final class ProductNameDeduplicationTests: XCTestCase {
    func testNameDedupeCarriesPurchaseStateToSurvivor() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(repository: repository, name: "Family")
        let firstID = UUID()
        let purchasedAt = Date().addingTimeInterval(120)
        try await seedNameDuplicates(
            persistence: persistence,
            familyID: familyID,
            listID: listID,
            rows: [
                DuplicateRow(id: firstID, name: "Milk", createdOffset: 0, purchasedAt: nil, buyer: nil),
                DuplicateRow(id: UUID(), name: "milk", createdOffset: 60, purchasedAt: purchasedAt, buyer: "Anna"),
                DuplicateRow(
                    id: UUID(),
                    name: " MILK ",
                    createdOffset: 90,
                    purchasedAt: purchasedAt.addingTimeInterval(-30),
                    buyer: "Boris"
                ),
            ]
        )

        let merged = try await repository.deduplicateProductsByName()

        XCTAssertEqual(merged, 2)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let states = try await nameDuplicateStates(ids: [firstID], persistence: persistence)
        let survivor = try XCTUnwrap(states.first)
        XCTAssertFalse(survivor.isDeleted)
        XCTAssertTrue(survivor.isPurchased)
        XCTAssertEqual(survivor.purchasedAt, purchasedAt)
        XCTAssertEqual(survivor.purchasedByName, "Anna")
    }

    func testNameDedupeSkipsRowsWithoutUpdatePermission() async throws {
        let (persistence, seedRepository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(repository: seedRepository, name: "Family")
        let ids = [UUID(), UUID()]
        try await seedNameDuplicates(
            persistence: persistence,
            familyID: familyID,
            listID: listID,
            rows: [
                DuplicateRow(id: ids[0], name: "Milk", createdOffset: 0, purchasedAt: nil, buyer: nil),
                DuplicateRow(id: ids[1], name: "milk", createdOffset: 60, purchasedAt: Date(), buyer: "Anna"),
            ]
        )
        let readOnlyRepository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: DenyAllPermissionAuthorizer()
        )

        let merged = try await readOnlyRepository.deduplicateProductsByName()

        XCTAssertEqual(merged, 0)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let rows = try await nameDuplicateStates(ids: ids, persistence: persistence)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { !$0.isDeleted })
        XCTAssertEqual(rows.first { $0.id == ids[0] }?.isPurchased, false)
    }

    private struct DuplicateRow {
        let id: UUID
        let name: String
        let createdOffset: TimeInterval
        let purchasedAt: Date?
        let buyer: String?
    }

    private struct DuplicateState {
        let id: UUID?
        let isDeleted: Bool
        let isPurchased: Bool
        let purchasedAt: Date?
        let purchasedByName: String?
    }

    private func nameDuplicateStates(
        ids: [UUID],
        persistence: PersistenceController
    ) async throws -> [DuplicateState] {
        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids.map { $0 as NSUUID })
            return try context.fetch(request).map {
                DuplicateState(
                    id: $0.id,
                    isDeleted: $0.deletedAt != nil,
                    isPurchased: $0.isPurchasedValue,
                    purchasedAt: $0.purchasedAt,
                    purchasedByName: $0.purchasedByName
                )
            }
        }
    }

    /// Bypasses addProduct so same-name rows coexist, as CloudKit delivers them from two devices.
    private func seedNameDuplicates(
        persistence: PersistenceController,
        familyID: UUID,
        listID: UUID,
        rows: [DuplicateRow]
    ) async throws {
        let base = Date()
        try await persistence.performBackgroundTask { context in
            let family = try FamilySpaceRepository.requireFamilySpace(id: familyID, in: context)
            guard let list = try FamilySpaceRepository.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            for row in rows {
                let product = ProductEntity(context: context)
                try persistence.assign(product, toSameStoreAs: family, in: context)
                product.id = row.id
                product.name = row.name
                product.quantity = NSNumber(value: 1)
                product.unit = ProductUnit.piece.rawValue
                product.category = ProductCategory.other.rawValue
                product.estimatedPrice = NSNumber(value: 0)
                product.isPurchased = NSNumber(value: row.purchasedAt != nil)
                product.purchasedAt = row.purchasedAt
                product.purchasedByName = row.buyer
                product.note = ""
                product.createdAt = base.addingTimeInterval(row.createdOffset)
                product.updatedAt = product.createdAt
                product.familySpace = family
                product.list = list
            }
        }
    }
}
