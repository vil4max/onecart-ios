import CloudKit
import Foundation

/// The iCloud identity other cart members see for this device's user.
protocol CloudUserIdentifying: AnyObject, Sendable {
    /// Advances whenever the identity is forgotten (sign-out, account deletion, iCloud account
    /// change); a record name read under an older value belongs to the previous user.
    var identityGeneration: UInt64 { get }
    /// The CloudKit user record name (`_abc…`), or nil while iCloud cannot tell.
    func currentUserRecordName() async -> String?
    /// Forgets the cached name and advances `identityGeneration`.
    func resetCachedUserRecordName()
}

/// The cached record name and the identity generation it was read under.
struct UserRecordNameCache: Sendable {
    private(set) var recordName: String?
    private(set) var generation: UInt64 = 0

    /// Forgets the name and invalidates every lookup that is still in flight.
    mutating func reset() {
        recordName = nil
        generation &+= 1
    }

    /// Stores a looked-up name only when no reset happened since the lookup started.
    @discardableResult
    mutating func store(_ name: String, readUnder lookupGeneration: UInt64) -> Bool {
        guard lookupGeneration == generation else { return false }
        recordName = name
        return true
    }
}

extension CloudKitBackendService: CloudUserIdentifying {
    var identityGeneration: UInt64 {
        userRecordNameCache.withLock { $0.generation }
    }

    func currentUserRecordName() async -> String? {
        guard persistence.cloudKitEnabled else { return nil }
        let (cached, lookupGeneration) = userRecordNameCache.withLock { ($0.recordName, $0.generation) }
        if let cached {
            return cached
        }
        let shareStore = shareStore
        do {
            let recordName = try await CloudKitDeadline.run(timeoutNanoseconds: 10_000_000_000) {
                try await shareStore.userRecordID().recordName
            }
            // The owner's own participant can read `__defaultOwner__`; only a real name is useful to others.
            guard !recordName.isEmpty, recordName != CKCurrentUserDefaultName else { return nil }
            let stored = userRecordNameCache.withLock { $0.store(recordName, readUnder: lookupGeneration) }
            return stored ? recordName : nil
        } catch {
            CartSyncLog.cart.error(
                "userRecordID fail error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
