import Foundation

enum CartSuggestionsEngine {
    static let defaultRussianSuggestions = [
        "Молоко", "Хлеб", "Яйца", "Сыр", "Сливочное масло",
        "Бананы", "Яблоки", "Кофе", "Чай", "Вода",
        "Куриное филе", "Помидоры", "Огурцы", "Картофель",
    ]

    static let defaultUkrainianSuggestions = [
        "Молоко", "Хліб", "Яйця", "Сир", "Вершкове масло",
        "Банани", "Яблука", "Кава", "Чай", "Вода",
        "Куряче філе", "Помідори", "Огірки", "Картопля",
    ]

    static let defaultEnglishSuggestions = [
        "Milk", "Bread", "Eggs", "Cheese", "Butter",
        "Bananas", "Apples", "Coffee", "Tea", "Water",
        "Chicken breast", "Tomatoes", "Cucumbers", "Potatoes",
    ]

    static func defaultEssentials(
        languageCode: String? = nil
    ) -> [String] {
        let code = languageCode ?? Locale.current.language.languageCode?.identifier
        if code == "uk" {
            return defaultUkrainianSuggestions
        }
        if code == "ru" {
            return defaultRussianSuggestions
        }
        return defaultEnglishSuggestions
    }

    /// History names by frequency descending, then alphabetically; one entry per
    /// case-insensitive name, keeping the casing of its first occurrence.
    private static func rankedHistoryNames(_ historyItemNames: [String]) -> [String] {
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

        let sortedKeys = frequencyMap.keys.sorted { key1, key2 in
            let count1 = frequencyMap[key1] ?? 0
            let count2 = frequencyMap[key2] ?? 0
            if count1 != count2 {
                return count1 > count2
            }
            return key1 < key2
        }
        return sortedKeys.compactMap { displayMap[$0] }
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
        // Same normalization as cart dedupe, so a name the cart would reject as a
        // duplicate ("Creme brulee" vs "Crème brûlée") is never suggested.
        let excludedSet = Set(
            currentCartItemNames
                .map(FamilyCartMerge.normalizedProductName)
                .filter { !$0.isEmpty }
        )

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Sorted history items first, followed by defaults.
        var candidates = rankedHistoryNames(historyItemNames)
        var seenKeys = Set(candidates.map { $0.lowercased() })

        for def in defaults {
            let name = def.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if !seenKeys.contains(key) {
                candidates.append(name)
                seenKeys.insert(key)
            }
        }

        let filtered = candidates.filter { name in
            let key = name.lowercased()
            if excludedSet.contains(FamilyCartMerge.normalizedProductName(name)) {
                return false
            }
            if trimmedQuery.isEmpty {
                return true
            }
            return key.contains(trimmedQuery)
        }

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

    /// Convenience overload for the screens' snapshots; History lines are already deduplicated
    /// across replicas, so a replicated purchase counts once (REQ-HIST-040).
    static func suggestions(
        from historyLines: [HistoryLine],
        currentCartItems: [CartItem],
        query: String = "",
        defaults: [String] = defaultEssentials(),
        limit: Int = 8
    ) -> [String] {
        let historyNames = historyLines.map(\.displayName)
        let cartNames = currentCartItems.map(\.displayName)
        return suggestions(
            historyItemNames: historyNames,
            currentCartItemNames: cartNames,
            query: query,
            defaults: defaults,
            limit: limit
        )
    }
}
