import CoreData
@testable import OneCart
import XCTest

extension CartItemsTests {
    func test_REQ_CART_090_sameNamedProductsReuseExistingCartLine() async throws {
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
        // Another member adds the same name with different casing/whitespace:
        // no second row — the existing line is returned.
        let secondID = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "  молоко ",
                quantity: 1,
                unit: .piece,
                category: .dairyEggs,
                estimatedPrice: 40,
                note: "",
                sourceURL: "https://shop.example.com/milk"
            ),
            createdByName: "Игорь"
        )

        XCTAssertEqual(firstID, secondID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let milk = space.sortedProducts.filter {
            FamilyCartMerge.normalizedProductName($0.displayName) == FamilyCartMerge.normalizedProductName("Молоко")
        }
        XCTAssertEqual(milk.count, 1, "Identical names must reuse one line")
        XCTAssertEqual(milk.first?.id, firstID)
    }

    func test_REQ_CART_090_reAddAfterDeleteCreatesNewLine() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Семья")
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let firstID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко")
        )
        try await repository.deleteProduct(id: firstID)
        let secondID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "молоко")
        )
        XCTAssertNotEqual(firstID, secondID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, secondID)
    }

    func test_REQ_CART_090_renameIntoExistingNameMergesRows() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Семья")
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let milkID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко")
        )
        let kefirID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Кефир")
        )
        try await repository.updateProduct(
            id: kefirID,
            draft: productDraft(name: " молоко ")
        )
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, milkID)
    }

    func test_REQ_CART_090_deduplicateProductsByNameKeepsFirstWriter() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Семья")
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(space.activeLists.first?.id)
        // Simulate two devices adding the same name with different stable IDs
        // (bypasses addProduct so both rows exist, as CloudKit would deliver).
        let firstID = UUID()
        let secondID = UUID()
        try await persistence.performBackgroundTask { context in
            let family = try FamilySpaceRepository.requireFamilySpace(id: familyID, in: context)
            guard let list = try FamilySpaceRepository.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            for (stableID, name, offset) in [
                (firstID, "Молоко", 0.0), (secondID, " молоко ", 60.0),
            ] as [(UUID, String, TimeInterval)] {
                let product = ProductEntity(context: context)
                try persistence.assign(product, toSameStoreAs: family, in: context)
                product.id = stableID
                product.name = name
                product.quantity = NSNumber(value: 1)
                product.unit = ProductUnit.piece.rawValue
                product.category = ProductCategory.other.rawValue
                product.estimatedPrice = NSNumber(value: 0)
                product.isPurchased = NSNumber(value: false)
                product.note = ""
                product.createdAt = Date().addingTimeInterval(offset)
                product.updatedAt = product.createdAt
                product.familySpace = family
                product.list = list
            }
        }
        let merged = try await repository.deduplicateProductsByName()
        XCTAssertEqual(merged, 1)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let reloaded = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(reloaded.sortedProducts.count, 1)
        XCTAssertEqual(reloaded.sortedProducts.first?.id, firstID)
    }

    func test_REQ_CART_090_duplicateNameIsDetectedBeyondFiftyLiveRows() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (_, listID, _) = try await seedCart(repository: repository)

        for index in 0..<60 {
            try await repository.addProduct(to: listID, draft: productDraft(name: "Filler \(index)"))
        }
        let lateID = try await repository.addProduct(to: listID, draft: productDraft(name: "Кефир"))

        let duplicateID = try await repository.addProduct(to: listID, draft: productDraft(name: " кефир "))

        XCTAssertEqual(duplicateID, lateID)
    }
}
