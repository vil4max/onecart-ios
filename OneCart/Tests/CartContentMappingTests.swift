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

    @Test("REQ-HIST-010: History maps to deduplicated lines that keep the archive order, fields and purchase day")
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
        #expect(lines.map(\.id) == entities.compactMap(\.id))
        for (line, entity) in zip(lines, entities) {
            #expect(line.displayName == entity.displayName)
            #expect(line.category == entity.categoryValue)
            #expect(line.purchaseMoment == entity.purchaseMoment)
            #expect(line.createdByName == entity.createdByName)
            #expect(line.purchasedByName == entity.purchasedByName)
        }
        #expect(lines.first { $0.id == breadID }?.createdByName == "Maria")
        #expect(lines.allSatisfy { $0.purchasedByName == "Alex" })

        let calendar = Calendar(identifier: .gregorian)
        let days = HistoryDayGroup.groups(from: lines, calendar: calendar)
        #expect(days.count == 1)
        #expect(days.first?.items.map(\.displayName) == ["Bread", "Milk"])
        #expect(days.first.map { calendar.isDate($0.dayStart, inSameDayAs: entities[0].purchaseMoment) } == true)
    }
}
