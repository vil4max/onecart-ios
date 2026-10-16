import Foundation
import UserNotifications

/// Cart activity banners for a shared cart (REQ-WIDGET-030), injected into the session so the
/// notification side effect stays behind a seam.
@MainActor
protocol CartActivityNotifying {
    func notifyIfNeeded(
        cartID: UUID,
        previous: [CartItemSnapshot],
        current: [CartItemSnapshot],
        currentUser: CartAuthor,
        isSharedCart: Bool
    )
    func clearSnapshots()
}

/// Keeps its snapshots in the session's defaults, so the composition root passes the same suite.
/// A nil center stores the snapshots and posts nothing (the test session builders).
struct LiveCartActivityNotifier: CartActivityNotifying {
    let defaults: UserDefaults
    let notificationCenter: UNUserNotificationCenter?

    func notifyIfNeeded(
        cartID: UUID,
        previous: [CartItemSnapshot],
        current: [CartItemSnapshot],
        currentUser: CartAuthor,
        isSharedCart: Bool
    ) {
        CartActivityNotifier.notifyIfNeeded(
            cartID: cartID,
            previous: previous,
            current: current,
            currentUserName: currentUser.displayName ?? "",
            currentUserRecordName: currentUser.recordName,
            isSharedCart: isSharedCart,
            defaults: defaults,
            notificationCenter: notificationCenter
        )
    }

    func clearSnapshots() {
        CartActivityNotifier.clearSnapshots(defaults: defaults)
    }
}

enum CartActivityNotifier {
    private static let snapshotKeyPrefix = "onecart.cart-activity-snapshot."

    private static func snapshotKey(cartID: UUID) -> String {
        snapshotKeyPrefix + cartID.uuidString
    }

    /// Snapshots carry item and member names. Sign-out and account deletion sweep them by
    /// prefix: the cart rows that named them may already be gone at that point.
    static func clearSnapshots(defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(snapshotKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    static func notifyIfNeeded(
        cartID: UUID,
        previous: [CartItemSnapshot],
        current: [CartItemSnapshot],
        currentUserName: String,
        currentUserRecordName: String? = nil,
        isSharedCart: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter? = .current()
    ) {
        let stored = loadStoredSnapshot(cartID: cartID, defaults: defaults)
        let diff = CartActivityDiff.evaluate(
            previous: previous,
            stored: stored,
            current: current,
            currentUserName: currentUserName,
            currentUserRecordName: currentUserRecordName,
            isSharedCart: isSharedCart
        )

        saveSnapshot(diff.nextSnapshot, cartID: cartID, defaults: defaults)

        guard diff.shouldNotify, let notificationCenter else { return }
        post(diff.events, to: notificationCenter)
    }

    private static func post(_ events: [CartActivityEvent], to notificationCenter: UNUserNotificationCenter) {
        notificationCenter.getNotificationSettings { settings in
            guard
                settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            else { return }

            for event in events {
                let content = UNMutableNotificationContent()
                content.sound = .default

                switch event {
                case let .itemsAdded(author, itemNames):
                    content.title = String(localized: "notify.items_added_title")
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

    static func requestAuthorizationIfNeeded(
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        notificationCenter.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            // Remote notifications are registered at every launch by AppDelegate; CloudKit's
            // silent pushes do not depend on this grant.
            notificationCenter.requestAuthorization(options: authorizationOptions) { _, _ in }
        }
    }

    /// Activity notifications show a banner with sound; the app never sets a badge.
    static let authorizationOptions: UNAuthorizationOptions = [.alert, .sound]

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
