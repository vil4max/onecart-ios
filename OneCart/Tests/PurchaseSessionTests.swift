import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class PurchaseSessionTests: XCTestCase {
    func testCompleteListArchivesProductsCreatesHistoryAndReplacementList() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Хлеб", quantity: 1, price: 38)
        )
        _ = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко", quantity: 1, price: 42)
        )
        try await repository.togglePurchased(
            id: try XCTUnwrap(
                try repository.fetchFamilySpace(id: familyID)?.sortedProducts.first?.id
            ),
            participantDisplayName: "Игорь"
        )

        let historyID = try await repository.completeList(id: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedProducts.isEmpty)
        XCTAssertEqual(space.activeLists.count, 1)
        XCTAssertNotEqual(space.activeLists.first?.id, listID)
        XCTAssertEqual(space.activeLists.first?.displayTitle, "Общий список")
        XCTAssertEqual(space.sortedHistory.count, 1)
        XCTAssertEqual(space.sortedHistory.first?.id, historyID)
        XCTAssertEqual(space.sortedHistory.first?.total?.doubleValue ?? 0, 80, accuracy: 0.001)
        XCTAssertTrue(space.sortedHistory.first?.memberNames?.contains("Игорь") == true)

        let completedRequest = ShoppingListEntity.fetchRequest()
        completedRequest.predicate = NSPredicate(format: "id == %@", listID as NSUUID)
        let completed = try XCTUnwrap(
            persistence.container.viewContext.fetch(completedRequest).first
        )
        XCTAssertEqual(completed.statusValue, .completed)
    }

    func testDeleteHistorySoftDeletesEntryAndItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(repository: repository)
        let historyID = try await repository.completeList(id: listID)

        try await repository.deleteHistory(id: historyID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedHistory.isEmpty)

        let request = PurchaseHistoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", historyID as NSUUID)
        let stored = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        XCTAssertNotNil(stored.deletedAt)
        let items = stored.items?.allObjects as? [HistoryItemEntity] ?? []
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.deletedAt != nil })
    }
}
