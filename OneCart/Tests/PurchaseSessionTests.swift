import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
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

@MainActor
final class PurchaseHistoryReplicaTests: XCTestCase {
    func testHistoryGroupsChooseSamePurchaseAcrossArchiveSessions() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Family")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let productID = UUID()
        let canonicalID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let replicaID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let canonical = try makeHistory(
            in: family,
            id: canonicalID,
            products: [(productID, "Bread")],
            purchasedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let replica = try makeHistory(
            in: family,
            id: replicaID,
            products: [(productID, "Replica bread")],
            purchasedAt: Date(timeIntervalSince1970: 2_000_000)
        )

        for entries in [[canonical, replica], [replica, canonical]] {
            let groups = HistoryDayGroup.groups(from: entries)
            XCTAssertEqual(groups.count, 1)
            XCTAssertEqual(groups.first?.items.map(\.displayName), ["Bread"])
            XCTAssertEqual(groups.first?.items.first?.history?.id, canonicalID)
        }

        XCTAssertEqual(canonical.sortedItems.count, 1)
        XCTAssertEqual(replica.sortedItems.count, 1)
        XCTAssertNil(replica.sortedItems.first?.deletedAt)
    }

    func testHistoryIdentityPreservesOtherFamiliesAndDistinctSameNamePurchases() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let firstID = try await repository.createFamilySpace(name: "First")
        let secondID = try await repository.createFamilySpace(name: "Second")
        let first = try XCTUnwrap(repository.fetchFamilySpace(id: firstID))
        let second = try XCTUnwrap(repository.fetchFamilySpace(id: secondID))
        let productID = UUID()
        let purchases = try makeHistory(
            in: first,
            products: [(productID, "Milk"), (UUID(), "Milk"), (nil, "Milk"), (nil, "Milk")]
        )
        let replica = try makeHistory(in: first, products: [(productID, "Milk")])
        let otherFamily = try makeHistory(in: second, products: [(productID, "Milk")])

        let items = HistoryDayGroup.groups(from: [purchases, replica, otherFamily]).flatMap(\.items)

        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items.filter { $0.familySpace?.id == firstID }.count, 4)
        XCTAssertEqual(items.filter { $0.familySpace?.id == secondID }.count, 1)
        XCTAssertEqual(items.filter { $0.id == nil }.count, 2)
    }

    func testArchiveRetryReusesExistingPurchaseAndArchivesOnlyNewItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, productID) = try await seedCart(repository: repository)
        try await repository.togglePurchased(id: productID, participantDisplayName: "First")
        let initialResult = try await repository.completePurchased(listID: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let originalHistoryID = try XCTUnwrap(initialResult)
        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let originalProduct = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        let originalObjectID = originalProduct.objectID
        let originalTombstone = try XCTUnwrap(originalProduct.deletedAt)
        try await insertStaleProduct(id: productID, listID: listID, persistence: persistence)

        let retryResult = try await repository.completePurchased(listID: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        XCTAssertEqual(retryResult, originalHistoryID)
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(family.sortedHistory.count, 1)
        XCTAssertEqual(family.sortedHistory.first?.sortedItems.count, 1)
        XCTAssertTrue(family.sortedProducts.isEmpty)
        let copies = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.allSatisfy { $0.deletedAt != nil })
        XCTAssertEqual(copies.first { $0.objectID == originalObjectID }?.deletedAt, originalTombstone)

        try await insertStaleProduct(id: productID, listID: listID, persistence: persistence)
        let freshID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Milk", price: 42)
        )
        try await repository.togglePurchased(id: freshID, participantDisplayName: "Second")
        let nextResult = try await repository.completePurchased(listID: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let nextID = try XCTUnwrap(nextResult)
        let updated = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let nextHistory = try XCTUnwrap(updated.sortedHistory.first { $0.id == nextID })

        XCTAssertNotEqual(nextID, originalHistoryID)
        XCTAssertEqual(updated.sortedHistory.count, 2)
        XCTAssertEqual(nextHistory.sortedItems.map(\.id), [freshID])
        XCTAssertEqual(nextHistory.totalValue, 42, accuracy: 0.001)
        XCTAssertEqual(nextHistory.memberNames, "Second")
        XCTAssertTrue(updated.sortedProducts.isEmpty)
    }

    private func makeHistory(
        in family: FamilySpace,
        id: UUID = UUID(),
        products: [(UUID?, String)],
        purchasedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) throws -> PurchaseHistoryEntity {
        let context = try XCTUnwrap(family.managedObjectContext)
        let history = PurchaseHistoryEntity(context: context)
        history.id = id
        history.familySpace = family
        history.date = purchasedAt
        for (productID, name) in products {
            let item = HistoryItemEntity(context: context)
            item.id = productID
            item.name = name
            item.purchasedAt = purchasedAt
            item.familySpace = family
            item.history = history
        }
        return history
    }

    private func insertStaleProduct(
        id: UUID,
        listID: UUID,
        persistence: PersistenceController
    ) async throws {
        try await persistence.performBackgroundTask { context in
            let list = try XCTUnwrap(FamilySpaceRepository.fetchList(id: listID, in: context))
            let product = ProductEntity(context: context)
            try persistence.assign(product, toSameStoreAs: list, in: context)
            product.id = id
            product.name = "Stale bread"
            product.isPurchased = true
            product.purchasedAt = Date(timeIntervalSince1970: 1_000_000)
            product.createdAt = product.purchasedAt
            product.familySpace = list.familySpace
            product.list = list
        }
    }
}
