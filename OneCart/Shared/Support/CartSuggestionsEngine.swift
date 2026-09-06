import Foundation

enum CartSuggestionsEngine {
    static let defaultRussianSuggestions = [
        "Молоко", "Хлеб", "Яйца", "Сыр", "Сливочное масло",
        "Бананы", "Яблоки", "Кофе", "Чай", "Вода",
        "Куриное филе", "Помидоры", "Огурцы", "Картофель",
    ]

    static let defaultEnglishSuggestions = [
        "Milk", "Bread", "Eggs", "Cheese", "Butter",
        "Bananas", "Apples", "Coffee", "Tea", "Water",
        "Chicken breast", "Tomatoes", "Cucumbers", "Potatoes",
    ]

    static func defaultEssentials(
        isRussian: Bool = Locale.current.language.languageCode?.identifier == "ru"
    ) -> [String] {
        isRussian ? defaultRussianSuggestions : defaultEnglishSuggestions
    }

    /// Pure suggestion extraction and ranking.
    ///
    /// - Parameters:
    ///   - historyItemNames: Item names retrieved from past shopping trips.
    ///   - currentCartItemNames: Item names currently in the active cart (to buy or in trolley).
    ///   - query: Current text entered in the search/add input field (optional).
    ///   - defaults: Fallback essential items to supplement history.
    ///   - limit: Maximum number of suggestions to return.
    /// - Returns: Ranked list of suggested product names.
    static func suggestions(
        historyItemNames: [String],
        currentCartItemNames: [String],
        query: String = "",
        defaults: [String] = defaultEssentials(),
        limit: Int = 8
    ) -> [String] {
        let excludedSet = Set(
            currentCartItemNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Tally history frequencies by lowercased key while preserving display casing
        var frequencyMap: [String: Int] = [:]
        var displayMap: [String: String] = [:]

        for rawName in historyItemNames {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            frequencyMap[key, default: 0] += 1
            if displayMap[key] == nil {
                displayMap[key] = name
            }
        }

        // 2. Sort history keys by frequency descending, then alphabetically
        let sortedHistoryKeys = frequencyMap.keys.sorted { key1, key2 in
            let count1 = frequencyMap[key1] ?? 0
            let count2 = frequencyMap[key2] ?? 0
            if count1 != count2 {
                return count1 > count2
            }
            return key1 < key2
        }

        // 3. Build candidate list: sorted history items first, followed by defaults
        var candidates: [String] = []
        var seenKeys = Set<String>()

        for key in sortedHistoryKeys {
            if let displayName = displayMap[key] {
                candidates.append(displayName)
                seenKeys.insert(key)
            }
        }

        for def in defaults {
            let name = def.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if !seenKeys.contains(key) {
                candidates.append(name)
                seenKeys.insert(key)
            }
        }

        // 4. Filter candidates:
        //    - Not currently in the active cart
        //    - Matches query (if query is provided)
        let filtered = candidates.filter { name in
            let key = name.lowercased()
            if excludedSet.contains(key) {
                return false
            }
            if trimmedQuery.isEmpty {
                return true
            }
            return key.contains(trimmedQuery)
        }

        // 5. Prioritize prefix matches when query is present
        let ranked: [String]
        if !trimmedQuery.isEmpty {
            let prefixMatches = filtered.filter { $0.lowercased().hasPrefix(trimmedQuery) }
            let otherMatches = filtered.filter { !$0.lowercased().hasPrefix(trimmedQuery) }
            ranked = prefixMatches + otherMatches
        } else {
            ranked = filtered
        }

        return Array(ranked.prefix(limit))
    }

    /// Convenience overload for Core Data entities.
    static func suggestions(
        from history: [PurchaseHistoryEntity],
        currentCartProducts: [ProductEntity],
        query: String = "",
        defaults: [String] = defaultEssentials(),
        limit: Int = 8
    ) -> [String] {
        let historyNames = history.flatMap(\.sortedItems).map(\.displayName)
        let cartNames = currentCartProducts.map(\.displayName)
        return suggestions(
            historyItemNames: historyNames,
            currentCartItemNames: cartNames,
            query: query,
            defaults: defaults,
            limit: limit
        )
    }
}
