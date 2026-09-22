import CloudKit
import Foundation

/// The iCloud identity other cart members see for this device's user.
protocol CloudUserIdentifying: AnyObject, Sendable {
    /// The CloudKit user record name (`_abc…`), or nil while iCloud cannot tell.
    func currentUserRecordName() async -> String?
}

extension CloudKitBackendService: CloudUserIdentifying {
    func currentUserRecordName() async -> String? {
        guard !persistence.inMemory, persistence.cloudKitEnabled else { return nil }
        if let cached = cachedUserRecordName.withLock({ $0 }) {
            return cached
        }
        let container = cloudContainer
        do {
            let recordName = try await CloudKitDeadline.run(timeoutNanoseconds: 10_000_000_000) {
                try await container.userRecordID().recordName
            }
            // The owner's own participant can read `__defaultOwner__`; only a real name is useful to others.
            guard !recordName.isEmpty, recordName != CKCurrentUserDefaultName else { return nil }
            cachedUserRecordName.withLock { $0 = recordName }
            return recordName
        } catch {
            CartSyncLog.cart.error(
                "userRecordID fail error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
