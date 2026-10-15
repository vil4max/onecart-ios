import Foundation
@testable import OneCart
import Testing

/// `CartContentStore` maps the Core Data entities into the screens' value snapshots once per
/// reload; the values must keep every field the screens read and the order the session sorts.
@MainActor
@Suite("CartContentMappingTests", .removesStores)
struct CartContentMappingTests {
    @Test("REQ-SHELL-010: cart lines map to values in cart order, newest to-buy first then completed, with fields")
    func cartLinesMapInCartOrderWithFields() async throws {
        let fixture = try await CartFixture.make()
        _ = try await fixture.repository.addProduct(
            to: fixture.listID,
            draft: .nameOnly("Bread"),
            createdByName: "Maria"
        )
        await fixture.settle()
        try await fixture.addProduct(named: "Soap", purchased: true)
        try await fixture.addProduct(named: "Milk")
        let store = CartContentStore(persistence: fixture.persistence)

        try store.reloadContent(familySpaceID: fixture.familyID)

        let entities = store.products(inListID: fixture.listID)
        let values = store.cartItems(inListID: fixture.listID)
        #expect(values.map(\.displayName) == ["Milk", "Bread", "Soap"])
        #expect(values.map(\.id) == entities.compactMap(\.id))
        for (value, entity) in zip(values, entities) {
            #expect(value.displayName == entity.displayName)
            #expect(value.category == entity.categoryValue)
            #expect(value.isPurchased == entity.isPurchasedValue)
            #expect(value.createdByName == entity.createdByName)
            #expect(value.purchasedByName == entity.purchasedByName)
        }
        #expect(values.first { $0.displayName == "Bread" }?.createdByName == "Maria")
        #expect(values.last?.purchasedByName == "Alex")

        #expect(store.cartLists.map(\.id) == store.activeLists.compactMap(\.id))
        #expect(CartList.primary(in: store.cartLists)?.id == fixture.listID)
        #expect(CartList.primary(in: store.cartLists)?.id == ShoppingListEntity.primaryList(in: store.activeLists)?.id)

        store.clearContent()
        #expect(store.cartLists.isEmpty)
        #expect(store.cartItems(inListID: fixture.listID).isEmpty)
    }

    @Test("REQ-HIST-010: History maps to lines that keep the archive order, fields and purchase day")
    func historyMapsToLinesWithFieldsAndDay() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.repository.addProduct(
            to: fixture.listID,
            draft: .nameOnly("Bread"),
            createdByName: "Maria"
        )
        try await fixture.repository.togglePurchased(id: breadID, participantDisplayName: "Alex")
        try await fixture.addProduct(named: "Milk", purchased: true)
        _ = try await fixture.repository.completePurchased(listID: fixture.listID)
        await fixture.settle()
        let store = CartContentStore(persistence: fixture.persistence)

        try store.reloadContent(familySpaceID: fixture.familyID)

        let entities = HistoryItems.unique(from: store.history)
        let lines = store.historyLines
        #expect(lines.count == 2)
        let familyID = fixture.familyID
        let lineID = { (productID: UUID) in HistoryLine.Identity.purchase(familyID: familyID, productID: productID) }
        #expect(lines.map(\.id) == entities.compactMap(\.id).map(lineID))
        for (line, entity) in zip(lines, entities) {
            #expect(line.displayName == entity.displayName)
            #expect(line.category == entity.categoryValue)
            #expect(line.purchaseMoment == entity.purchaseMoment)
            #expect(line.createdByName == entity.createdByName)
            #expect(line.purchasedByName == entity.purchasedByName)
        }
        #expect(lines.first { $0.id == lineID(breadID) }?.createdByName == "Maria")
        #expect(lines.allSatisfy { $0.purchasedByName == "Alex" })

        let calendar = Calendar(identifier: .gregorian)
        let days = HistoryDayGroup.groups(from: lines, calendar: calendar)
        #expect(days.count == 1)
        #expect(days.first?.items.map(\.displayName) == ["Bread", "Milk"])
        #expect(days.first.map { calendar.isDate($0.dayStart, inSameDayAs: entities[0].purchaseMoment) } == true)
    }
}

// MARK: - Rows a sync can deliver

extension CartContentMappingTests {
    typealias ProductRow = (id: UUID?, name: String, createdAt: Date)

    @Test("REQ-CART-090: two rows with one product ID in a list show as one line, the first in cart order")
    func repeatedProductIDKeepsTheFirstRow() async throws {
        let fixture = try await CartFixture.make()
        let sharedID = UUID()
        let now = Date()
        try await insertProducts(
            [
                (sharedID, "Milk", now.addingTimeInterval(60)),
                (sharedID, "Milk copy", now),
                (UUID(), "Bread", now.addingTimeInterval(-60)),
            ],
            into: fixture
        )
        let store = CartContentStore(persistence: fixture.persistence)

        try store.reloadContent(familySpaceID: fixture.familyID)

        let values = store.cartItems(inListID: fixture.listID)
        #expect(values.map(\.displayName) == ["Milk", "Bread"])
        #expect(Set(values.map(\.id)).count == values.count)
        #expect(store.products(inListID: fixture.listID).map(\.displayName) == ["Milk", "Bread"])
    }

    @Test("REQ-WIDGET-010: a product without an ID is left out of the lines the widgets, the trip and Siri count")
    func productWithoutIDIsLeftOutOfEverySurface() async throws {
        let fixture = try await CartFixture.make()
        let now = Date()
        try await insertProducts(
            [(nil, "Ghost", now), (UUID(), "Bread", now.addingTimeInterval(-60))],
            into: fixture
        )
        let store = CartContentStore(persistence: fixture.persistence)

        try store.reloadContent(familySpaceID: fixture.familyID)

        #expect(store.products.count == 2)
        #expect(store.cartItems(inListID: fixture.listID).map(\.displayName) == ["Bread"])
        #expect(store.products(inListID: fixture.listID).map(\.displayName) == ["Bread"])
    }

    @Test("REQ-SHELL-010: a primary list without an ID leaves the cart without a list instead of picking another")
    func primaryListWithoutIDGivesTheCartNoList() async throws {
        let fixture = try await CartFixture.make()
        let status = try fixture.list.status
        let persistence = fixture.persistence
        let familyID = fixture.familyID
        // Newer than the household list, so it sorts first and the rule picks it.
        try await persistence.performBackgroundTask { context in
            let family = try FamilySpaceRepository.requireFamilySpace(id: familyID, in: context)
            let list = ShoppingListEntity(context: context)
            try persistence.assign(list, toSameStoreAs: family, in: context)
            list.status = status
            list.createdAt = Date().addingTimeInterval(3600)
            list.updatedAt = list.createdAt
            list.familySpace = family
        }
        await fixture.settle()
        let store = CartContentStore(persistence: fixture.persistence)

        try store.reloadContent(familySpaceID: fixture.familyID)

        #expect(store.activeLists.count == 2)
        let primary = try #require(ShoppingListEntity.primaryList(in: store.activeLists))
        #expect(primary.id == nil)
        #expect(store.cartLists.isEmpty)
        #expect(CartList.primary(in: store.cartLists) == nil)
    }

    @Test("REQ-SYNC-010: a background edit reaches the cart lines on the next product refresh")
    func refreshProductsPicksUpBackgroundEdits() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let store = CartContentStore(persistence: fixture.persistence)
        try store.reloadContent(familySpaceID: fixture.familyID)
        #expect(store.cartItems(inListID: fixture.listID).map(\.displayName) == ["Bread"])

        let familyID = fixture.familyID
        try await fixture.repository.updateProduct(id: breadID, familySpaceID: familyID, draft: .nameOnly("Rye"))
        try await fixture.repository.togglePurchased(id: breadID, participantDisplayName: "Alex")
        await fixture.settle()
        try store.refreshProducts(familySpaceID: fixture.familyID)

        let line = try #require(store.cartItems(inListID: fixture.listID).first)
        #expect(line.id == breadID)
        #expect(line.displayName == "Rye")
        #expect(line.isPurchased)
        #expect(line.purchasedByName == "Alex")
    }

    @Test("REQ-HIST-040: a purchase whose replica lands on the next History page shows once after loading it")
    func loadMoreHistoryDeduplicatesAcrossPages() async throws {
        let fixture = try await CartFixture.make()
        let context = fixture.persistence.container.viewContext
        let family = try fixture.family
        let breadID = UUID()
        let pageSize = CartContentStore.historyPageSize
        let now = Date()
        // The newest entry and the oldest, one past the first page, archive the same product.
        for index in 0...pageSize {
            let entry = PurchaseHistoryEntity(context: context)
            try fixture.persistence.assign(entry, toSameStoreAs: family, in: context)
            entry.id = UUID()
            entry.total = NSNumber(value: 0)
            entry.date = now.addingTimeInterval(TimeInterval(-index))
            entry.createdAt = entry.date
            entry.updatedAt = entry.date
            entry.familySpace = family
            entry.memberNames = "Alex"
            let item = HistoryItemEntity(context: context)
            try fixture.persistence.assign(item, toSameStoreAs: family, in: context)
            let isBread = index == 0 || index == pageSize
            item.id = isBread ? breadID : UUID()
            item.name = isBread ? "Bread" : "Item \(index)"
            item.purchasedAt = entry.date
            item.familySpace = family
            item.history = entry
        }
        try context.save()
        let store = CartContentStore(persistence: fixture.persistence)
        let breadLine = HistoryLine.Identity.purchase(familyID: fixture.familyID, productID: breadID)

        try store.reloadContent(familySpaceID: fixture.familyID)
        #expect(store.historyHasMore)
        #expect(store.historyLines.filter { $0.id == breadLine }.count == 1)

        try store.loadMoreHistory(familySpaceID: fixture.familyID)

        #expect(store.history.count == pageSize + 1)
        #expect(store.historyHasMore == false)
        #expect(store.historyLines.count == pageSize)
        #expect(store.historyLines.filter { $0.id == breadLine }.count == 1)
    }

    /// Writes product rows straight into the store, as a sync can deliver them.
    private func insertProducts(_ rows: [ProductRow], into fixture: CartFixture) async throws {
        let persistence = fixture.persistence
        let familyID = fixture.familyID
        let listID = fixture.listID
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
                product.unit = "piece"
                product.category = ProductCategory.other.rawValue
                product.estimatedPrice = NSNumber(value: 0)
                product.isPurchased = NSNumber(value: false)
                product.note = ""
                product.createdAt = row.createdAt
                product.updatedAt = row.createdAt
                product.familySpace = family
                product.list = list
            }
        }
        await fixture.settle()
    }
}
