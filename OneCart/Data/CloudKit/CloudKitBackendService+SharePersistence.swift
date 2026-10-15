import CloudKit
import CoreData
import Foundation

extension CloudKitBackendService {
    func persist(
        _ share: CKShare,
        in store: NSPersistentStore,
        timeoutNanoseconds: UInt64 = 22_000_000_000
    ) async throws -> CKShare {
        let persistence = persistence
        // The store reference is only handed back to the container; it is never mutated here.
        nonisolated(unsafe) let store = store
        return try await CloudKitDeadline.run(timeoutNanoseconds: timeoutNanoseconds) {
            try await Self.persistWithoutTimeout(share, in: store, persistence: persistence)
        }
    }

    private static func persistWithoutTimeout(
        _ share: CKShare,
        in store: NSPersistentStore,
        persistence: PersistenceController
    ) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            persistence.container.persistUpdatedShare(share, in: store) { savedShare, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedShare {
                    continuation.resume(returning: savedShare)
                } else {
                    continuation.resume(throwing: OneCartCloudKitError.shareURLUnavailable)
                }
            }
        }
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            cloudContainer.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}
