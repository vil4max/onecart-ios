import Foundation
import os
import Synchronization

/// Shared by the app and the widget, so it imports no UI framework: each target defines its
/// live `shared` instance with WidgetCenter reloads, and tests inject their own closure.
public final class WidgetSnapshotStore: Sendable {
    private let suiteName: String
    private let snapshotKey = "onecart.widget.snapshot"
    private let pendingDirectoryURL: URL?
    private let reloadTimelines: @Sendable () -> Void
    private let mutex = Mutex<Void>(())

    private static let logger = Logger(subsystem: OneCartLog.subsystem, category: "WidgetSnapshot")

    /// No fallback to `.standard`: in the extension that is a different domain, so a
    /// fallback would hide a broken App Group behind a widget that never updates.
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public init(
        suiteName: String = OneCartAppGroup.identifier,
        pendingDirectoryURL: URL? = nil,
        reloadTimelines: @escaping @Sendable () -> Void
    ) {
        self.suiteName = suiteName
        self.reloadTimelines = reloadTimelines
        self.pendingDirectoryURL =
            pendingDirectoryURL
            ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: OneCartAppGroup.identifier)?
            .appendingPathComponent("WidgetPurchases", isDirectory: true)
        // Logged once per store; `shared` lives for the whole process.
        if UserDefaults(suiteName: suiteName) == nil {
            Self.logger.fault("Widget defaults suite unavailable: \(suiteName, privacy: .public)")
        }
        if self.pendingDirectoryURL == nil {
            Self.logger.fault("App Group container unavailable; widget purchases are disabled")
        }
    }

    public func save(snapshot: WidgetCartSnapshot) {
        let saved = mutex.withLock { _ -> Bool in
            guard let userDefaults, let data = try? JSONEncoder().encode(snapshot) else { return false }
            userDefaults.set(data, forKey: snapshotKey)
            return true
        }
        // Outside the lock: the injected closure may read the store, and Mutex is not reentrant.
        if saved { reloadTimelines() }
    }

    /// Fills the accent of a snapshot that carries none from the accent the app last wrote
    /// to this store's suite, so the widget draws the chosen accent before the app writes
    /// a snapshot with one. The store reads the suite; the snapshot value never does.
    public func withStoredAccent(_ snapshot: WidgetCartSnapshot) -> WidgetCartSnapshot {
        snapshot.fillingMissingAccent(with: userDefaults?.string(forKey: OneCartAppGroup.accentColorKey))
    }

    public func loadSnapshot() -> WidgetCartSnapshot? {
        mutex.withLock { _ in
            guard let userDefaults,
                let data = userDefaults.data(forKey: snapshotKey)
            else {
                return nil
            }
            return try? JSONDecoder().decode(WidgetCartSnapshot.self, from: data)
        }
    }

    public func enqueuePurchase(_ request: WidgetPurchaseRequest) throws {
        try mutex.withLock { _ in
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
    }

    public func pendingPurchases() throws -> [WidgetPurchaseRequest] {
        try mutex.withLock { _ in
            guard let pendingDirectoryURL else { return [] }
            guard FileManager.default.fileExists(atPath: pendingDirectoryURL.path) else { return [] }
            let urls = try FileManager.default.contentsOfDirectory(
                at: pendingDirectoryURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "json" }
            var requests: [WidgetPurchaseRequest] = []
            for url in urls {
                do {
                    let request = try JSONDecoder().decode(WidgetPurchaseRequest.self, from: Data(contentsOf: url))
                    guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == request.id else {
                        Self.quarantine(url)
                        continue
                    }
                    requests.append(request)
                } catch is DecodingError {
                    // Keep malformed data for inspection; one damaged request must not block valid purchases.
                    Self.quarantine(url)
                } catch {
                    // A read failure can be transient (file protection while locked), so the
                    // file stays in place for the next pass instead of being quarantined.
                    let reason = error.localizedDescription
                    Self.logger.error("Skipping unreadable widget purchase: \(reason, privacy: .public)")
                }
            }
            return requests.sorted {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }
        }
    }

    /// Never throws: a file that cannot be moved aside is skipped on this pass
    /// rather than failing every valid command next to it.
    private static func quarantine(_ url: URL) {
        let destination = url.appendingPathExtension("invalid")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            logger.error("Could not quarantine widget purchase: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func acknowledgePurchase(id: UUID) throws {
        try mutex.withLock { _ in
            guard let pendingDirectoryURL else { throw WidgetPurchaseError.unavailable }
            let url = pendingDirectoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    public func clear() throws {
        try mutex.withLock { _ in
            userDefaults?.removeObject(forKey: snapshotKey)
            userDefaults?.removeObject(forKey: "onecart.widget.pending_toggles")
            if let pendingDirectoryURL, FileManager.default.fileExists(atPath: pendingDirectoryURL.path) {
                try FileManager.default.removeItem(at: pendingDirectoryURL)
            }
        }
        reloadTimelines()
    }
}

public enum WidgetPurchaseError: LocalizedError {
    case invalidRequest
    case unavailable

    public var errorDescription: String? {
        String(localized: "sync.generic_failure")
    }
}
