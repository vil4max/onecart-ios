import Foundation
import UIKit
import UserNotifications

public struct CartItemSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let isPurchased: Bool
    public let createdByName: String?
    public let purchasedByName: String?

    public init(
        id: UUID,
        name: String,
        isPurchased: Bool,
        createdByName: String? = nil,
        purchasedByName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isPurchased = isPurchased
        self.createdByName = createdByName
        self.purchasedByName = purchasedByName
    }
}

public enum CartActivityEvent: Equatable, Sendable {
    case itemsAdded(author: String, itemNames: [String])
    case allPurchased(author: String)
}

public enum CartActivityDiff {
    public struct Result: Equatable, Sendable {
        public var events: [CartActivityEvent]
        public var nextSnapshot: [CartItemSnapshot]
        public var shouldNotify: Bool

        public init(events: [CartActivityEvent], nextSnapshot: [CartItemSnapshot], shouldNotify: Bool) {
            self.events = events
            self.nextSnapshot = nextSnapshot
            self.shouldNotify = shouldNotify
        }
    }

    public static func evaluate(
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
        let baselineMap = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        let normalizedUser = currentUserName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var events: [CartActivityEvent] = []

        // 1. Detect items added by partner
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

        // 2. Detect "All Purchased" by partner
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

public enum CartActivityNotifier {
    private static func snapshotKey(cartID: UUID) -> String {
        "onecart.cart-activity-snapshot.\(cartID.uuidString)"
    }

    public static func notifyIfNeeded(
        cartID: UUID,
        previous: [CartItemSnapshot],
        current: [CartItemSnapshot],
        currentUserName: String,
        isSharedCart: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        let stored = loadStoredSnapshot(cartID: cartID, defaults: defaults)
        let diff = CartActivityDiff.evaluate(
            previous: previous,
            stored: stored,
            current: current,
            currentUserName: currentUserName,
            isSharedCart: isSharedCart
        )

        saveSnapshot(diff.nextSnapshot, cartID: cartID, defaults: defaults)

        guard diff.shouldNotify else { return }

        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            else { return }

            for event in diff.events {
                let content = UNMutableNotificationContent()
                content.sound = .default

                switch event {
                case let .itemsAdded(author, itemNames):
                    content.title = "OneCart Family"
                    if itemNames.count == 1, let single = itemNames.first {
                        content.body = String(
                            localized: "notify.item_added_single \(author) \(single)"
                        )
                    } else if itemNames.count > 1, let first = itemNames.first {
                        let remaining = itemNames.count - 1
                        content.body = String(
                            localized: "notify.items_added_multiple \(author) \(first) \(remaining)"
                        )
                    } else {
                        continue
                    }
                case let .allPurchased(author):
                    content.title = String(localized: "notify.all_purchased_title")
                    content.body = String(localized: "notify.all_purchased_body \(author)")
                }

                let request = UNNotificationRequest(
                    identifier: "cart-activity-\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                notificationCenter.add(request)
            }
        }
    }

    public static func requestAuthorizationIfNeeded(
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }

    public static func clearSnapshot(cartID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: snapshotKey(cartID: cartID))
    }

    private static func loadStoredSnapshot(cartID: UUID, defaults: UserDefaults) -> [CartItemSnapshot] {
        guard let data = defaults.data(forKey: snapshotKey(cartID: cartID)),
              let items = try? JSONDecoder().decode([CartItemSnapshot].self, from: data)
        else {
            return []
        }
        return items
    }

    private static func saveSnapshot(_ items: [CartItemSnapshot], cartID: UUID, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: snapshotKey(cartID: cartID))
        }
    }
}
