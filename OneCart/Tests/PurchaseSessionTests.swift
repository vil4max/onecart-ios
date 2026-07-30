import CloudKit
import CoreData
@testable import OneCart
import XCTest

final class PurchaseSessionTests: XCTestCase {
    func testCompletePurchasedMovesOnlyCheckedItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, breadID) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Хлеб", quantity: 1, price: 38)
        )
        let milkID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко", quantity: 1, price: 42)
        )
        try await repository.togglePurchased(
            id: breadID,
            participantDisplayName: "Игорь"
        )

        let completedHistoryID = try await repository.completePurchased(listID: listID)
        let historyID = try XCTUnwrap(completedHistoryID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedHistory.count, 1)
        let history = try XCTUnwrap(space.sortedHistory.first)
        XCTAssertEqual(history.id, historyID)
        XCTAssertEqual(history.sortedItems.count, 1)
        XCTAssertEqual(history.sortedItems.first?.displayName, "Хлеб")
        XCTAssertEqual(history.totalValue, 38, accuracy: 0.001)
        XCTAssertEqual(history.memberNames, "Игорь")

        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, milkID)
        XCTAssertEqual(space.sortedProducts.first?.displayName, "Молоко")
        XCTAssertEqual(space.activeLists.first?.id, listID)
        XCTAssertEqual(space.activeLists.first?.statusValue, .active)
    }

    func testCompletePurchasedWithoutChecksDoesNothing() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, productID) = try await seedCart(repository: repository)

        let historyID = try await repository.completePurchased(listID: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        XCTAssertNil(historyID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedHistory.isEmpty)
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, productID)
        XCTAssertEqual(space.activeLists.first?.id, listID)
    }

    func testDeleteHistorySoftDeletesEntryAndItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, productID) = try await seedCart(repository: repository)
        try await repository.togglePurchased(
            id: productID,
            participantDisplayName: "Игорь"
        )
        let completedHistoryID = try await repository.completePurchased(listID: listID)
        let historyID = try XCTUnwrap(completedHistoryID)

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

    func testArchivePurchasedBeforeMovesOnlyStaleCheckedItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, breadID) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Хлеб", quantity: 1, price: 38)
        )
        let milkID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко", quantity: 1, price: 42)
        )
        try await repository.togglePurchased(id: breadID, participantDisplayName: "Игорь")
        try await repository.togglePurchased(id: milkID, participantDisplayName: "Игорь")

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: startOfToday))

        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", breadID as NSUUID)
            request.fetchLimit = 1
            let bread = try XCTUnwrap(context.fetch(request).first)
            bread.purchasedAt = yesterday
            bread.updatedAt = yesterday
        }
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let historyID = try await repository.archivePurchasedBefore(
            listID: listID,
            cutoff: startOfToday
        )
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        XCTAssertNotNil(historyID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedHistory.count, 1)
        XCTAssertEqual(space.sortedHistory.first?.sortedItems.count, 1)
        XCTAssertEqual(space.sortedHistory.first?.sortedItems.first?.displayName, "Хлеб")
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, milkID)
        XCTAssertTrue(space.sortedProducts.first?.isPurchasedValue == true)
    }

    func testDeleteHistoryItemsSoftDeletesItemsAndEmptySession() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, productID) = try await seedCart(repository: repository)
        try await repository.togglePurchased(
            id: productID,
            participantDisplayName: "Игорь"
        )
        let completedHistoryID = try await repository.completePurchased(listID: listID)
        let historyID = try XCTUnwrap(completedHistoryID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let itemID = try XCTUnwrap(space.sortedHistory.first?.sortedItems.first?.id)
        try await repository.deleteHistoryItems(ids: [itemID])
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let refreshed = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(refreshed.sortedHistory.isEmpty)

        let request = PurchaseHistoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", historyID as NSUUID)
        let stored = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        XCTAssertNotNil(stored.deletedAt)
    }

    func testHistoryDayGroupsByPurchasedAt() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, breadID) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Хлеб", quantity: 1, price: 38)
        )
        let milkID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко", quantity: 1, price: 42)
        )
        try await repository.togglePurchased(id: breadID, participantDisplayName: "Игорь")
        try await repository.togglePurchased(id: milkID, participantDisplayName: "Игорь")

        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: startOfToday))
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: startOfToday))

        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", [breadID, milkID].map { $0 as NSUUID })
            for product in try context.fetch(request) {
                if product.id == breadID {
                    product.purchasedAt = yesterday
                } else {
                    product.purchasedAt = twoDaysAgo
                }
            }
        }
        _ = try await repository.completePurchased(listID: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let groups = HistoryDayGroup.groups(from: space.sortedHistory, calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].dayStart, yesterday)
        XCTAssertEqual(groups[0].items.map(\.displayName), ["Хлеб"])
        XCTAssertEqual(groups[1].dayStart, twoDaysAgo)
        XCTAssertEqual(groups[1].items.map(\.displayName), ["Молоко"])
    }
}
