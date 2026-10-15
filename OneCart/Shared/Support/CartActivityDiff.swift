import Foundation

enum CartActivityEvent: Equatable, Sendable {
    case itemsAdded(author: String, itemNames: [String])
    case allPurchased(author: String)
}

enum CartActivityDiff {
    struct Result: Equatable, Sendable {
        var events: [CartActivityEvent]
        var nextSnapshot: [CartItemSnapshot]
        var shouldNotify: Bool
    }

    static func evaluate(
        previous: [CartItemSnapshot],
        stored: [CartItemSnapshot],
        current: [CartItemSnapshot],
        currentUserName: String,
        isSharedCart: Bool
    ) -> Result {
        guard isSharedCart else {
            return Result(events: [], nextSnapshot: current, shouldNotify: false)
        }

        // Baseline seeding on first launch: learn existing items without notifying
        if previous.isEmpty && stored.isEmpty {
            return Result(events: [], nextSnapshot: current, shouldNotify: false)
        }

        let baseline = previous.isEmpty ? stored : previous
        let baselineIDs = Set(baseline.map(\.id))
        // Replica rows can share an id until launch dedupe runs; keep the first instead of trapping.
        let baselineMap = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let normalizedUser = currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var events: [CartActivityEvent] = []

        let newItems = current.filter { !baselineIDs.contains($0.id) }
        var itemsByAuthor: [String: [String]] = [:]

        for item in newItems {
            let author = item.createdByName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !author.isEmpty, author.lowercased() != normalizedUser else {
                continue
            }
            itemsByAuthor[author, default: []].append(item.name)
        }

        for (author, names) in itemsByAuthor {
            events.append(.itemsAdded(author: author, itemNames: names))
        }

        let previouslyHadUnpurchased = baseline.contains(where: { !$0.isPurchased })
        let currentlyAllPurchased = !current.isEmpty && current.allSatisfy(\.isPurchased)

        if previouslyHadUnpurchased, currentlyAllPurchased {
            let newlyCompleted = current.filter { currentItem in
                if let old = baselineMap[currentItem.id] {
                    return !old.isPurchased && currentItem.isPurchased
                }
                return currentItem.isPurchased
            }

            let completingAuthor = newlyCompleted.compactMap(\.purchasedByName).first { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && trimmed.lowercased() != normalizedUser
            }

            if let author = completingAuthor {
                events.append(.allPurchased(author: author))
            }
        }

        return Result(
            events: events,
            nextSnapshot: current,
            shouldNotify: !events.isEmpty
        )
    }
}
