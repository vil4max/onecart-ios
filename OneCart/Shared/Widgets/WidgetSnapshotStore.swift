import Foundation
#if canImport(WidgetKit)
    import WidgetKit
#endif

public final class WidgetSnapshotStore: @unchecked Sendable {
    public static let shared = WidgetSnapshotStore()

    private let userDefaults: UserDefaults?
    private let snapshotKey = "onecart.widget.snapshot"
    private let pendingTogglesKey = "onecart.widget.pending_toggles"
    private let lock = NSLock()

    public init(suiteName: String = OneCartAppGroup.identifier) {
        userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func save(snapshot: WidgetCartSnapshot) {
        lock.lock()
        defer { lock.unlock() }

        guard let userDefaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: snapshotKey)
            #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    public func loadSnapshot() -> WidgetCartSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        guard let userDefaults,
              let data = userDefaults.data(forKey: snapshotKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetCartSnapshot.self, from: data)
    }

    @discardableResult
    public func toggleItem(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let userDefaults else { return false }
        guard let data = userDefaults.data(forKey: snapshotKey),
              var snapshot = try? JSONDecoder().decode(WidgetCartSnapshot.self, from: data)
        else {
            return false
        }

        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let newPurchased = !snapshot.items[index].isPurchased
        var updatedItems = snapshot.items
        updatedItems[index].isPurchased = newPurchased

        // Recalculate counts
        // Items are only a display window; preserve counts for products outside it.
        let purchasedCount = min(snapshot.totalCount, max(0, snapshot.purchasedCount + (newPurchased ? 1 : -1)))
        snapshot = WidgetCartSnapshot(
            cartTitle: snapshot.cartTitle,
            totalCount: snapshot.totalCount,
            purchasedCount: purchasedCount,
            isSyncing: snapshot.isSyncing,
            lastUpdated: Date(),
            familyMemberCount: snapshot.familyMemberCount,
            activePartnerName: snapshot.activePartnerName,
            themeRaw: snapshot.themeRaw,
            accentColorRaw: snapshot.accentColorRaw,
            items: updatedItems
        )

        if let encoded = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(encoded, forKey: snapshotKey)
        }

        // Record pending toggle for AppSession reconciliation
        var pending = userDefaults.stringArray(forKey: pendingTogglesKey) ?? []
        pending.append(id.uuidString)
        userDefaults.set(pending, forKey: pendingTogglesKey)

        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
        #endif

        return true
    }

    public func drainPendingToggles() -> [UUID] {
        lock.lock()
        defer { lock.unlock() }

        guard let userDefaults else { return [] }
        let raw = userDefaults.stringArray(forKey: pendingTogglesKey) ?? []
        userDefaults.removeObject(forKey: pendingTogglesKey)
        return raw.compactMap { UUID(uuidString: $0) }
    }
}
