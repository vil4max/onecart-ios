import Foundation
@testable import OneCart

/// Reports a fixed CloudKit user record name; nil behaves like iCloud that cannot answer.
final class FakeCloudUserIdentity: CloudUserIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var recordName: String?
    private var calls = 0
    private var generation: UInt64 = 0
    private var lookupHook: (@Sendable () async -> Void)?

    init(recordName: String?) {
        self.recordName = recordName
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    var identityGeneration: UInt64 {
        lock.withLock { generation }
    }

    /// Runs while a lookup is in flight, before it answers.
    func duringLookup(_ hook: @escaping @Sendable () async -> Void) {
        lock.withLock { lookupHook = hook }
    }

    func currentUserRecordName() async -> String? {
        let hook = lock.withLock {
            calls += 1
            return lookupHook
        }
        await hook?()
        return lock.withLock { recordName }
    }

    func resetCachedUserRecordName() {
        lock.withLock { generation &+= 1 }
    }
}
