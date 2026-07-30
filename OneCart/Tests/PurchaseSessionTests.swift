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
        XCTAssertEqual(history.sortedItems.first?.purchasedByName, "Игорь")
        XCTAssertNotNil(history.sortedItems.first?.purchasedAt)
        XCTAssertEqual(history.totalValue, 38, accuracy: 0.001)
        XCTAssertEqual(history.memberNames, "Игорь")

        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, milkID)
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
        XCTAssertEqual(space.sortedProducts.first?.id, productID)
        XCTAssertEqual(space.activeLists.first?.id, listID)
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
        let startOfToday = calendar.startOfDay(for: Date())
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
        XCTAssertEqual(space.sortedHistory.first?.sortedItems.map(\.displayName), ["Хлеб"])
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertEqual(space.sortedProducts.first?.id, milkID)
        XCTAssertTrue(space.sortedProducts.first?.isPurchasedValue == true)
    }

    func testArchivePurchasedBeforeKeepsItemsPurchasedAtStartOfToday() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, productID) = try await seedCart(repository: repository)
        try await repository.togglePurchased(id: productID, participantDisplayName: "Игорь")

        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: Date())

        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
            request.fetchLimit = 1
            let product = try XCTUnwrap(context.fetch(request).first)
            product.purchasedAt = startOfToday
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

        XCTAssertNil(historyID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedHistory.isEmpty)
        XCTAssertEqual(space.sortedProducts.count, 1)
        XCTAssertTrue(space.sortedProducts.first?.isPurchasedValue == true)
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

    func testHistoryDayFormattingTodayAndYesterday() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        XCTAssertEqual(
            HistoryDayFormatting.title(for: today, calendar: calendar, now: now),
            String(localized: "history.day_today")
        )
        XCTAssertEqual(
            HistoryDayFormatting.title(for: yesterday, calendar: calendar, now: now),
            String(localized: "history.day_yesterday")
        )
    }

    @MainActor
    func testArchiveStalePurchasedIfNeededViaSession() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Игорь")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Семья",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(
            familyID.uuidString,
            forKey: "onecart.active-family-space-id.\(account.id.uuidString)"
        )
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let staleID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Хлеб")
        )
        let freshID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко")
        )
        try await repository.togglePurchased(id: staleID, participantDisplayName: "Игорь")
        try await repository.togglePurchased(id: freshID, participantDisplayName: "Игорь")

        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: startOfToday))

        try await persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", staleID as NSUUID)
            request.fetchLimit = 1
            let product = try XCTUnwrap(context.fetch(request).first)
            product.purchasedAt = yesterday
        }

        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertTrue(session.canEdit)

        await session.archiveStalePurchasedIfNeeded(now: now, calendar: calendar)

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedHistory.count, 1)
        XCTAssertEqual(space.sortedHistory.first?.sortedItems.map(\.displayName), ["Хлеб"])
        XCTAssertEqual(space.sortedProducts.map(\.id), [freshID])
        XCTAssertTrue(space.sortedProducts.first?.isPurchasedValue == true)
    }
}
