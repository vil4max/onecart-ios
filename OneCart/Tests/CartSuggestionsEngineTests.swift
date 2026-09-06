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
}
