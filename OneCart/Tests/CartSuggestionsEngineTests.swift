import CoreData
import Foundation
@testable import OneCart
import Testing

@Suite("CartSuggestionsEngineTests")
struct CartSuggestionsEngineTests {
    @Test("Ranks suggestions by purchase frequency descending")
    func ranksByFrequency() {
        let history = [
            "Молоко",
            "Хлеб",
            "Молоко",
            "Яйца",
            "Молоко",
            "Хлеб",
        ]
        // Frequency: Молоко (3), Хлеб (2), Яйца (1)
        let suggestions = CartSuggestionsEngine.suggestions(
            historyItemNames: history,
            currentCartItemNames: [],
            defaults: [],
            limit: 3
        )

        #expect(suggestions == ["Молоко", "Хлеб", "Яйца"])
    }

    @Test("Excludes items already present in the active cart")
    func excludesCurrentCartItems() {
        let history = ["Молоко", "Хлеб", "Яйца", "Сыр"]
        let currentCart = ["хлеб", "Сыр"] // Case-insensitive check

        let suggestions = CartSuggestionsEngine.suggestions(
            historyItemNames: history,
            currentCartItemNames: currentCart,
            defaults: [],
            limit: 5
        )

        #expect(suggestions == ["Молоко", "Яйца"])
        #expect(!suggestions.contains("Хлеб"))
        #expect(!suggestions.contains("Сыр"))
    }

    @Test("Falls back to defaults when history is empty")
    func defaultsWhenHistoryEmpty() {
        let defaults = ["Хлеб", "Молоко", "Яйца", "Сыр"]
        let currentCart = ["Молоко"]

        let suggestions = CartSuggestionsEngine.suggestions(
            historyItemNames: [],
            currentCartItemNames: currentCart,
            defaults: defaults,
            limit: 3
        )

        #expect(suggestions == ["Хлеб", "Яйца", "Сыр"])
    }

    @Test("Filters suggestions by typed query and prioritizes prefix match")
    func queryFilteringAndPrefixMatch() {
        let history = ["Шоколад молочный", "Молоко", "Морковь", "Хлеб"]

        let suggestions = CartSuggestionsEngine.suggestions(
            historyItemNames: history,
            currentCartItemNames: [],
            query: "мол",
            defaults: [],
            limit: 5
        )

        // "Молоко" starts with "мол", "Шоколад молочный" contains "мол"
        #expect(suggestions.first == "Молоко")
        #expect(suggestions.contains("Шоколад молочный"))
        #expect(!suggestions.contains("Морковь"))
        #expect(!suggestions.contains("Хлеб"))
    }

    @Test("Case-insensitively normalizes duplicate names and preserves first casing")
    func caseNormalization() {
        let history = ["молоко", "Молоко", "МОЛОКО"]

        let suggestions = CartSuggestionsEngine.suggestions(
            historyItemNames: history,
            currentCartItemNames: [],
            defaults: [],
            limit: 5
        )

        #expect(suggestions.count == 1)
        #expect(suggestions.first?.lowercased() == "молоко")
    }

    @Test("Respects output limit")
    func respectsLimit() {
        let history = ["A", "B", "C", "D", "E", "F"]

        let suggestions = CartSuggestionsEngine.suggestions(
            historyItemNames: history,
            currentCartItemNames: [],
            defaults: [],
            limit: 3
        )

        #expect(suggestions.count == 3)
    }

    @Test("Returns appropriate default essentials for language code")
    func essentialsForLanguageCode() {
        let uk = CartSuggestionsEngine.defaultEssentials(languageCode: "uk")
        #expect(uk.contains("Хліб"))
        #expect(uk.contains("Кава"))

        let ru = CartSuggestionsEngine.defaultEssentials(languageCode: "ru")
        #expect(ru.contains("Хлеб"))
        #expect(ru.contains("Кофе"))

        let en = CartSuggestionsEngine.defaultEssentials(languageCode: "en")
        #expect(en.contains("Bread"))
        #expect(en.contains("Coffee"))
    }

    @MainActor
    @Test("Counts replicated purchases once per family when ranking suggestions")
    func replicatedPurchasesDoNotInflateFrequency() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let context = persistence.container.viewContext
        let firstFamily = FamilySpace(context: context)
        firstFamily.id = UUID()
        let secondFamily = FamilySpace(context: context)
        secondFamily.id = UUID()
        let milkID = UUID()
        let milkCopies = (0 ..< 3).map { _ in
            makeHistory(in: firstFamily, productID: milkID, name: "Milk", context: context)
        }
        let firstBread = makeHistory(in: firstFamily, productID: UUID(), name: "Bread", context: context)
        let secondBread = makeHistory(in: firstFamily, productID: UUID(), name: "Bread", context: context)
        let otherFamilyMilk = makeHistory(in: secondFamily, productID: milkID, name: "Milk", context: context)

        let firstSuggestions = CartSuggestionsEngine.suggestions(
            from: milkCopies + [firstBread, secondBread],
            currentCartProducts: [],
            defaults: []
        )
        let acrossFamilies = CartSuggestionsEngine.suggestions(
            from: milkCopies + [firstBread, otherFamilyMilk],
            currentCartProducts: [],
            defaults: []
        )

        #expect(firstSuggestions == ["Bread", "Milk"])
        #expect(acrossFamilies == ["Milk", "Bread"])
        #expect(milkCopies.flatMap(\.sortedItems).count == 3)
    }

    @MainActor
    private func makeHistory(
        in family: FamilySpace,
        productID: UUID,
        name: String,
        context: NSManagedObjectContext
    ) -> PurchaseHistoryEntity {
        let history = PurchaseHistoryEntity(context: context)
        history.id = UUID()
        history.familySpace = family
        let item = HistoryItemEntity(context: context)
        item.id = productID
        item.name = name
        item.familySpace = family
        item.history = history
        return history
    }
}
