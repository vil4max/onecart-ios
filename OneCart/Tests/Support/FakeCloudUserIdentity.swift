import Foundation
@testable import OneCart

/// Reports a fixed CloudKit user record name; nil behaves like iCloud that cannot answer.
final class FakeCloudUserIdentity: CloudUserIdentifying, @unchecked Sendable {
    private let lock = NSLock()
    private var recordName: String?
    private var calls = 0

    init(recordName: String?) {
        self.recordName = recordName
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func currentUserRecordName() async -> String? {
        lock.withLock {
            calls += 1
            return recordName
        }
    }
}
