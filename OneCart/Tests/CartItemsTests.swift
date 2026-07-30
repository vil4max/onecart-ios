import CloudKit
import CoreData
@testable import OneCart
import XCTest

final class CartItemsTests: XCTestCase {
    func testTogglePurchasedSetsAndClearsBuyer() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (_, listID, productID) = try await seedCart(repository: repository)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        persistence.container.viewContext.refreshAllObjects()
        var product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedByName, "Анна")
        XCTAssertNotNil(product.purchasedAt)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        persistence.container.viewContext.refreshAllObjects()
        product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertFalse(product.isPurchasedValue)
        XCTAssertNil(product.purchasedByName)
        XCTAssertNil(product.purchasedAt)
        _ = listID
    }

    func testDeleteProductSkipsPurchasedItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, _, productID) = try await seedCart(repository: repository)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        try await repository.deleteProduct(id: productID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, productID)
        XCTAssertTrue(space.sortedProducts.first?.isPurchasedValue == true)
        XCTAssertNil(space.sortedProducts.first?.deletedAt)
    }

    func testSortedProductsPutsNewestToBuyFirstThenCompleted() async throws {
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

    func testUpdateProductRewritesFields() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (_, _, productID) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Молоко", quantity: 1, price: 40)
        )

        try await repository.updateProduct(
            id: productID,
            draft: productDraft(name: "Молоко 2.5%", quantity: 2, price: 55, note: "холодное")
        )

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(product.displayName, "Молоко 2.5%")
        XCTAssertEqual(product.quantityValue, 2, accuracy: 0.001)
        XCTAssertEqual(product.estimatedPriceValue, 55, accuracy: 0.001)
        XCTAssertEqual(product.note, "холодное")
    }

    func testDeletedProductIsKeptAsSyncTombstoneAndHiddenFromUI() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Offline")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(family.activeLists.first?.id)
        let productID = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Хлеб",
                quantity: 1,
                unit: .piece,
                category: .other,
                estimatedPrice: 38,
                note: ""
            )
        )

        try await repository.deleteProduct(id: productID)

        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let stored = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        XCTAssertNotNil(stored.deletedAt)
        XCTAssertTrue(try XCTUnwrap(repository.fetchFamilySpace(id: familyID)).sortedProducts.isEmpty)
    }

    func testSameNamedProductsStayAsSeparateCartLines() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Семья")
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let draft = ProductDraft(
            name: "Молоко",
            quantity: 1,
            unit: .piece,
            category: .dairyEggs,
            estimatedPrice: 40,
            note: "",
            sourceURL: "https://shop.example.com/milk"
        )

        let firstID = try await repository.addProduct(
            to: listID,
            draft: draft,
            createdByName: "Анна"
        )
        let secondID = try await repository.addProduct(
            to: listID,
            draft: draft,
            createdByName: "Игорь"
        )

        XCTAssertNotEqual(firstID, secondID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let milk = space.sortedProducts.filter { $0.displayName == "Молоко" }
        XCTAssertEqual(milk.count, 2, "Identical names must not be summed into one line")
        XCTAssertEqual(
            milk.map(\.quantityValue).reduce(0, +),
            2,
            "Each line keeps its own quantity"
        )
    }

    func testInvalidNamesAreRejected() async throws {
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
            name: AppModel.defaultFamilyName,
            isHouseholdDefault: true
        )
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let list = try XCTUnwrap(family.activeLists.first)
        let listID = try XCTUnwrap(list.id)

        let productID = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Молоко",
                quantity: 2,
                unit: .piece,
                category: .dairyEggs,
                estimatedPrice: 42,
                note: "2.5%"
            )
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

    func testAddProductVisibleAfterViewContextMerge() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Sync")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(family.activeLists.first?.id)

        _ = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Яйца",
                quantity: 10,
                unit: .piece,
                category: .dairyEggs,
                estimatedPrice: 65,
                note: ""
            )
        )

        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let products = try persistence.container.viewContext.fetch(ProductEntity.fetchRequest())
            .filter { $0.familySpace?.id == familyID && $0.deletedAt == nil }
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.displayName, "Яйца")
    }
}
