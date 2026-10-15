import CoreData
@testable import OneCart
import XCTest

@MainActor
final class FamilyCartMergeTests: XCTestCase {
    func testNormalizedProductNameIgnoresCaseAndSurroundingWhitespace() {
        XCTAssertEqual(
            FamilyCartMerge.normalizedProductName("  Молоко "),
            FamilyCartMerge.normalizedProductName("молоко")
        )
    }

    func testDefaultFamilyNameIsStable() {
        let expected = String(localized: String.LocalizationValue("cart.default_title"))
        XCTAssertEqual(AppSession.defaultFamilyName, expected)
        XCTAssertFalse(AppSession.defaultFamilyName.isEmpty)
    }
}

@MainActor
final class PersonalCartContentRestoreTests: XCTestCase {
    func test_REQ_SYNC_040_restoreKeepsStableIDsHistoryAndSourceGraphAcrossRetries() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let accountID = UUID()
        let sourceID = try await repository.createFamilySpace(name: "Local", cachedForUserID: accountID)
        let destinationID = try await repository.createFamilySpace(name: "Existing", cachedForUserID: accountID)
        let source = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID))
        let destination = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        let sourceListID = try XCTUnwrap(source.activeLists.first?.id)
        let destinationListID = try XCTUnwrap(destination.activeLists.first?.id)
        let firstID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Bread"))
        let secondID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Baguette"))
        let historyProductID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Eggs"))
        try await repository.togglePurchased(id: historyProductID, participantDisplayName: "Shopper")
        let historyResult = try await repository.completePurchased(listID: sourceListID)
        let historyID = try XCTUnwrap(historyResult)
        let completedID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Milk"))
        try await repository.togglePurchased(id: completedID, participantDisplayName: "Shopper")
        let remoteID = try await repository.addProduct(to: destinationListID, draft: productDraft(name: "Bread"))

        for _ in 0..<2 {
            let restored = try await repository.restoreProvisionalPersonalContent(
                from: sourceID, into: destinationID, accountID: accountID
            )
            XCTAssertTrue(restored)
        }
        await persistence.container.viewContext.perform { persistence.container.viewContext.processPendingChanges() }
        let restored = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        XCTAssertEqual(Set(restored.sortedProducts.compactMap(\.id)), [firstID, secondID, completedID, remoteID])
        XCTAssertEqual(restored.sortedProducts.filter { $0.displayName == "Bread" }.count, 2)
        XCTAssertTrue(restored.sortedProducts.first { $0.id == completedID }?.isPurchasedValue == true)
        XCTAssertEqual(restored.sortedProducts.first { $0.id == completedID }?.purchasedByName, "Shopper")
        XCTAssertEqual(restored.sortedHistory.map(\.id), [historyID])
        XCTAssertEqual(restored.sortedHistory.first?.sortedItems.map(\.id), [historyProductID])
        XCTAssertEqual(restored.sortedHistory.first?.sortedItems.first?.purchasedByName, "Shopper")
        XCTAssertEqual(restored.sortedHistory.first?.familySpace?.id, destinationID)
        let original = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID))
        XCTAssertEqual(Set(original.sortedProducts.compactMap(\.id)), [firstID, secondID, completedID])
        XCTAssertEqual(original.sortedHistory.first?.id, historyID)
        XCTAssertNil(original.deletedAt)

        try await repository.updateProduct(
            id: firstID, familySpaceID: destinationID,
            draft: productDraft(name: "Destination edit"))
        await persistence.container.viewContext.perform { persistence.container.viewContext.processPendingChanges() }
        XCTAssertEqual(
            try repository.fetchFamilySpace(id: destinationID)?.sortedProducts.first { $0.id == firstID }?
                .displayName, "Destination edit")
        XCTAssertEqual(
            try repository.fetchFamilySpace(id: sourceID)?.sortedProducts.first { $0.id == firstID }?
                .displayName, "Bread")
        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "familySpace.id == %@ AND id == %@", destinationID as NSUUID,
            historyProductID as NSUUID)
        XCTAssertNotNil(try persistence.container.viewContext.fetch(request).first?.deletedAt)
    }

    func testRestorePreservesDestinationTombstoneAndOtherAccountBoundary() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let accountID = UUID()
        let sourceID = try await repository.createFamilySpace(name: "Local", cachedForUserID: accountID)
        let destinationID = try await repository.createFamilySpace(name: "Existing", cachedForUserID: accountID)
        let sourceListID = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID)?.activeLists.first?.id)
        let destinationListID = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID)?.activeLists.first?.id)
        let productID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Bread"))
        _ = try await repository.addProduct(to: destinationListID, id: productID, draft: productDraft(name: "Deleted"))
        try await repository.deleteProduct(id: productID, familySpaceID: destinationID)

        do {
            _ = try await repository.restoreProvisionalPersonalContent(
                from: sourceID, into: destinationID, accountID: UUID()
            )
            XCTFail("Expected permissionDenied")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }
        let restored = try await repository.restoreProvisionalPersonalContent(
            from: sourceID, into: destinationID, accountID: accountID
        )
        await persistence.container.viewContext.perform { persistence.container.viewContext.processPendingChanges() }

        XCTAssertTrue(restored)
        XCTAssertTrue(try XCTUnwrap(repository.fetchFamilySpace(id: destinationID)).sortedProducts.isEmpty)
        XCTAssertEqual(try repository.fetchFamilySpace(id: sourceID)?.sortedProducts.first?.id, productID)
        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "familySpace.id == %@", destinationID as NSUUID)
        let products = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(products.count, 1)
        XCTAssertNotNil(products.first?.deletedAt)
        XCTAssertEqual(products.first?.name, "Deleted")
    }
}
