import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class CartItemsTests: XCTestCase {
    func test_REQ_CART_040_REQ_SYNC_020_togglePurchasedSetsAndClearsBuyer() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (_, listID, productID) = try await seedCart(repository: repository)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        var snapshot = try await purchasedBuyerSnapshot(
            productID: productID,
            in: persistence.container.viewContext
        )
        XCTAssertTrue(snapshot.isPurchased)
        XCTAssertEqual(snapshot.purchasedByName, "Анна")
        XCTAssertNotNil(snapshot.purchasedAt)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        snapshot = try await purchasedBuyerSnapshot(
            productID: productID,
            in: persistence.container.viewContext
        )
        XCTAssertFalse(snapshot.isPurchased)
        XCTAssertNil(snapshot.purchasedByName)
        XCTAssertNil(snapshot.purchasedAt)
        _ = listID
    }

    func test_REQ_CART_050_deleteProductSkipsPurchasedItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, _, productID) = try await seedCart(repository: repository)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        try await repository.deleteProduct(id: productID, familySpaceID: familyID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, productID)
        XCTAssertTrue(space.sortedProducts.first?.isPurchasedValue == true)
        XCTAssertNil(space.sortedProducts.first?.deletedAt)
    }

    func test_REQ_SHELL_010_sortedProductsPutsNewestToBuyFirstThenCompleted() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, olderID) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Старое")
        )
        let newerID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Новое")
        )
        try await repository.togglePurchased(id: olderID, participantDisplayName: "Анна")

        let calendar = Calendar(identifier: .gregorian)
        let olderDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: -2, to: Date()))
        let newerDate = try XCTUnwrap(calendar.date(byAdding: .hour, value: -1, to: Date()))

        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "id IN %@",
                [olderID, newerID].map { $0 as NSUUID }
            )
            for product in try context.fetch(request) {
                if product.id == olderID {
                    product.createdAt = olderDate
                } else {
                    product.createdAt = newerDate
                }
            }
        }
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedProducts.map(\.displayName), ["Новое", "Старое"])
        XCTAssertFalse(space.sortedProducts[0].isPurchasedValue)
        XCTAssertTrue(space.sortedProducts[1].isPurchasedValue)
    }

    /// An item is a name plus state (REQ-CART-020) with no money (REQ-CART-060): the draft holds the
    /// name and its category only, a new line leaves every legacy attribute unset, and an edit
    /// leaves the values an older build stored on the line untouched.
    func test_REQ_CART_020_draftCarriesOnlyWhatTheCartEdits() async throws {
        XCTAssertEqual(
            Mirror(reflecting: ProductDraft(name: "Хлеб", category: .other)).children.compactMap(\.label),
            ["name", "category"]
        )

        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, _, productID) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "  Молоко ")
        )
        let added = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(added.name, "Молоко")
        XCTAssertNil(added.quantity)
        XCTAssertNil(added.unit)
        XCTAssertNil(added.estimatedPrice)
        XCTAssertNil(added.note)

        let catalogDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
            let legacy = try XCTUnwrap(context.fetch(request).first)
            legacy.quantity = NSNumber(value: 2)
            legacy.unit = "kg"
            legacy.estimatedPrice = NSNumber(value: 55)
            legacy.originalPrice = NSNumber(value: 60)
            legacy.loyaltyPrice = NSNumber(value: 50)
            legacy.note = "холодное"
            legacy.imageURL = "https://shop.example.com/milk.png"
            legacy.sourceURL = "https://shop.example.com/milk"
            legacy.catalogFetchedAt = catalogDate
            legacy.promotionEndsAt = catalogDate
        }

        try await repository.updateProduct(
            id: productID,
            familySpaceID: familyID,
            draft: ProductDraft(name: "Молоко 2.5%", category: .dairyEggs)
        )

        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
            let product = try XCTUnwrap(context.fetch(request).first)
            XCTAssertEqual(product.name, "Молоко 2.5%")
            XCTAssertEqual(product.categoryValue, .dairyEggs)
            XCTAssertEqual(product.quantity, NSNumber(value: 2))
            XCTAssertEqual(product.unit, "kg")
            XCTAssertEqual(product.estimatedPrice, NSNumber(value: 55))
            XCTAssertEqual(product.originalPrice, NSNumber(value: 60))
            XCTAssertEqual(product.loyaltyPrice, NSNumber(value: 50))
            XCTAssertEqual(product.note, "холодное")
            XCTAssertEqual(product.imageURL, "https://shop.example.com/milk.png")
            XCTAssertEqual(product.sourceURL, "https://shop.example.com/milk")
            XCTAssertEqual(product.catalogFetchedAt, catalogDate)
            XCTAssertEqual(product.promotionEndsAt, catalogDate)
        }

        // Completing the line still carries the stored legacy values into History.
        let listID = try XCTUnwrap(fetchProduct(id: productID, repository: repository)?.list?.id)
        try await repository.togglePurchased(id: productID, participantDisplayName: "Игорь")
        try await repository.completePurchased(listID: listID)
        try await persistence.performBackgroundTask { context in
            let request = HistoryItemEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
            let item = try XCTUnwrap(context.fetch(request).first)
            XCTAssertEqual(item.quantity, NSNumber(value: 2))
            XCTAssertEqual(item.unit, "kg")
            XCTAssertEqual(item.estimatedPrice, NSNumber(value: 55))
            XCTAssertEqual(item.note, "холодное")
            XCTAssertEqual(item.sourceURL, "https://shop.example.com/milk")
        }
    }

    func test_REQ_SYNC_030_deletedProductIsKeptAsSyncTombstoneAndHiddenFromUI() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Offline")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(family.activeLists.first?.id)
        let productID = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(name: "Хлеб", category: .other)
        )

        try await repository.deleteProduct(id: productID, familySpaceID: familyID)

        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let stored = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        XCTAssertNotNil(stored.deletedAt)
        XCTAssertTrue(try XCTUnwrap(repository.fetchFamilySpace(id: familyID)).sortedProducts.isEmpty)
    }

    func test_REQ_CART_030_invalidNamesAreRejected() async throws {
        let (_, repository) = try await makeInMemoryRepository()

        do {
            _ = try await repository.createFamilySpace(name: "   ")
            XCTFail("Expected invalidName")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidName)
        }

        let familyID = try await repository.createFamilySpace(name: "OK")
        let listID = try XCTUnwrap(
            try repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )

        do {
            _ = try await repository.addProduct(
                to: listID,
                draft: productDraft(name: " \n\t ")
            )
            XCTFail("Expected invalidName")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidName)
        }

        do {
            try await repository.renameFamilySpace(id: familyID, name: " ")
            XCTFail("Expected invalidName")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidName)
        }
    }

    func testAddProductLandsInSameStoreAsFamilyForCloudKitSync() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(
            name: AppSession.defaultFamilyName,
            isHouseholdDefault: true
        )
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let list = try XCTUnwrap(family.activeLists.first)
        let listID = try XCTUnwrap(list.id)

        let productID = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(name: "Молоко", category: .dairyEggs)
        )

        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let product = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)

        XCTAssertEqual(product.displayName, "Молоко")
        XCTAssertEqual(product.list?.id, listID)
        XCTAssertEqual(product.familySpace?.id, familyID)
        XCTAssertEqual(product.isPurchasedValue, false)
        XCTAssertEqual(
            product.objectID.persistentStore?.url,
            family.objectID.persistentStore?.url,
            "Product must share the FamilySpace store or CloudKit will not sync the share graph"
        )
        XCTAssertEqual(persistence.scope(for: product), .private)

        let reloaded = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(reloaded.sortedProducts.count, 1)
        XCTAssertEqual(reloaded.sortedProducts.first?.id, productID)
    }

    func test_REQ_CART_030_addProductVisibleAfterViewContextMerge() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Sync")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(family.activeLists.first?.id)

        _ = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(name: "Яйца", category: .dairyEggs)
        )

        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let products = try persistence.container.viewContext.fetch(ProductEntity.fetchRequest())
            .filter { $0.familySpace?.id == familyID && $0.deletedAt == nil }
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.displayName, "Яйца")
    }

    func testBusyFlagStaysSetUntilLastOverlappingOperationEnds() throws {
        let defaults = try makeDefaults()
        let session = try makeTestSession(
            persistence: makeInMemoryPersistence(),
            defaults: defaults
        )

        session.beginBusyOperation()
        session.beginBusyOperation()
        XCTAssertTrue(session.isBusy)

        session.endBusyOperation()
        XCTAssertTrue(session.isBusy, "One operation is still running")

        session.endBusyOperation()
        XCTAssertFalse(session.isBusy)

        // An unbalanced end must not push the counter below zero and wedge the flag.
        session.endBusyOperation()
        session.beginBusyOperation()
        session.endBusyOperation()
        XCTAssertFalse(session.isBusy)
    }

    private func purchasedBuyerSnapshot(
        productID: UUID,
        in context: NSManagedObjectContext
    ) async throws -> (isPurchased: Bool, purchasedByName: String?, purchasedAt: Date?) {
        try await context.perform {
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
            request.fetchLimit = 1
            let product = try XCTUnwrap(context.fetch(request).first)
            return (
                product.isPurchasedValue,
                product.purchasedByName,
                product.purchasedAt
            )
        }
    }
}
