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

    /// The user the diff must not notify about their own changes.
    private struct CurrentUser {
        let normalizedName: String
        let recordName: String?

        /// CloudKit identity decides when both sides carry one, so two members with the same
        /// display name still tell each other apart. A line an older client wrote, or one written
        /// before the session learned its record name, falls back to the display name.
        func authored(name: String, recordName authorRecordName: String?) -> Bool {
            if let recordName, let authorRecordName = authorRecordName?.nilIfBlank {
                return authorRecordName == recordName
            }
            return name.lowercased() == normalizedName
        }
    }

    static func evaluate(
        previous: [CartItemSnapshot],
        stored: [CartItemSnapshot],
        current: [CartItemSnapshot],
        currentUserName: String,
        currentUserRecordName: String? = nil,
        isSharedCart: Bool
    ) -> Result {
        // Baseline seeding on first launch: learn existing items without notifying
        guard isSharedCart, !(previous.isEmpty && stored.isEmpty) else {
            return Result(events: [], nextSnapshot: current, shouldNotify: false)
        }

        let baseline = previous.isEmpty ? stored : previous
        let user = CurrentUser(
            normalizedName: currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            recordName: currentUserRecordName?.nilIfBlank
        )
        var events = addedEvents(baseline: baseline, current: current, user: user)
        if let author = completingAuthor(baseline: baseline, current: current, user: user) {
            events.append(.allPurchased(author: author))
        }
        return Result(
            events: events,
            nextSnapshot: current,
            shouldNotify: !events.isEmpty
        )
    }

    private static func addedEvents(
        baseline: [CartItemSnapshot],
        current: [CartItemSnapshot],
        user: CurrentUser
    ) -> [CartActivityEvent] {
        let baselineIDs = Set(baseline.map(\.id))
        var itemsByAuthor: [String: [String]] = [:]
        for item in current where !baselineIDs.contains(item.id) {
            let author = item.createdByName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !author.isEmpty, !user.authored(name: author, recordName: item.createdByRecordName) else {
                continue
            }
            itemsByAuthor[author, default: []].append(item.name)
        }
        return itemsByAuthor.map { author, names in
            .itemsAdded(author: author, itemNames: names)
        }
    }

    /// The partner who checked the last open line, when the cart has just become all purchased.
    private static func completingAuthor(
        baseline: [CartItemSnapshot],
        current: [CartItemSnapshot],
        user: CurrentUser
    ) -> String? {
        let previouslyHadUnpurchased = baseline.contains(where: { !$0.isPurchased })
        let currentlyAllPurchased = !current.isEmpty && current.allSatisfy(\.isPurchased)
        guard previouslyHadUnpurchased, currentlyAllPurchased else { return nil }

        // Replica rows can share an id until launch dedupe runs; keep the first instead of trapping.
        let baselineMap = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newlyCompleted = current.filter { currentItem in
            if let old = baselineMap[currentItem.id] {
                return !old.isPurchased && currentItem.isPurchased
            }
            return currentItem.isPurchased
        }
        return newlyCompleted.first { item in
            guard let name = item.purchasedByName else { return false }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && !user.authored(name: trimmed, recordName: item.purchasedByRecordName)
        }?.purchasedByName
    }
}
