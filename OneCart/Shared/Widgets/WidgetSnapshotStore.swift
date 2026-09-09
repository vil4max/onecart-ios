import Foundation
#if canImport(WidgetKit)
    import WidgetKit
#endif

public final class WidgetSnapshotStore: @unchecked Sendable {
    public static let shared = WidgetSnapshotStore()

    private let userDefaults: UserDefaults?
    private let snapshotKey = "onecart.widget.snapshot"
    private let pendingDirectoryURL: URL?
    private let lock = NSLock()

    public init(
        suiteName: String = OneCartAppGroup.identifier,
        pendingDirectoryURL: URL? = nil
    ) {
        userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.pendingDirectoryURL = pendingDirectoryURL ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: OneCartAppGroup.identifier)?
            .appendingPathComponent("WidgetPurchases", isDirectory: true)
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
            accountID: snapshot.accountID,
            familyID: snapshot.familyID,
            items: updatedItems
        )

        if let encoded = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(encoded, forKey: snapshotKey)
        }

        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
        #endif

        return true
    }

    public func enqueuePurchase(_ request: WidgetPurchaseRequest) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let pendingDirectoryURL else { throw WidgetPurchaseError.unavailable }
        try FileManager.default.createDirectory(at: pendingDirectoryURL, withIntermediateDirectories: true)
        let url = pendingDirectoryURL.appendingPathComponent(request.id.uuidString).appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try JSONDecoder().decode(WidgetPurchaseRequest.self, from: Data(contentsOf: url))
            guard existing.accountID == request.accountID, existing.familyID == request.familyID,
                  existing.productID == request.productID, existing.isPurchased == request.isPurchased
            else { throw WidgetPurchaseError.invalidRequest }
            return
        }
        try JSONEncoder().encode(request).write(to: url, options: .atomic)
    }

    public func pendingPurchases() throws -> [WidgetPurchaseRequest] {
        lock.lock()
        defer { lock.unlock() }
        guard let pendingDirectoryURL else { return [] }
        guard FileManager.default.fileExists(atPath: pendingDirectoryURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: pendingDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var requests: [WidgetPurchaseRequest] = []
        for url in urls {
            do {
                let request = try JSONDecoder().decode(WidgetPurchaseRequest.self, from: Data(contentsOf: url))
                guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == request.id else {
                    try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("invalid"))
                    continue
                }
                requests.append(request)
            } catch is DecodingError {
                // Keep malformed data for inspection; one damaged request must not block valid purchases.
                try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("invalid"))
            }
        }
        return requests.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    public func acknowledgePurchase(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let pendingDirectoryURL else { throw WidgetPurchaseError.unavailable }
        let url = pendingDirectoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func clear() throws {
        lock.lock()
        defer {
            lock.unlock()
            #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        userDefaults?.removeObject(forKey: snapshotKey)
        userDefaults?.removeObject(forKey: "onecart.widget.pending_toggles")
        if let pendingDirectoryURL, FileManager.default.fileExists(atPath: pendingDirectoryURL.path) {
            try FileManager.default.removeItem(at: pendingDirectoryURL)
        }
    }

    public func clearPendingPurchases() throws {
        lock.lock()
        defer { lock.unlock() }
        if let pendingDirectoryURL, FileManager.default.fileExists(atPath: pendingDirectoryURL.path) {
            try FileManager.default.removeItem(at: pendingDirectoryURL)
        }
        userDefaults?.removeObject(forKey: "onecart.widget.pending_toggles")
    }
}

public enum WidgetPurchaseError: LocalizedError {
    case invalidRequest
    case unavailable

    public var errorDescription: String? {
        String(localized: "sync.generic_failure")
    }
}
