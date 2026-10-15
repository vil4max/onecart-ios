import CloudKit
import CoreData
import Foundation
import Synchronization

/// The container calls the share code makes: share lookup, creation and persistence, the zone
/// purge of a leave, and the iCloud account. `LiveCloudKitShareStore` is the only conformer that
/// reaches `NSPersistentCloudKitContainer` or `CKContainer` for shares; tests inject a fake so
/// timeouts, late callbacks and door persists run without iCloud. Stores are named by scope, so
/// a fake needs no `NSPersistentStore`.
protocol CloudKitShareStoring: Sendable {
    func fetchShares(matching objectIDs: [NSManagedObjectID]) throws -> [NSManagedObjectID: CKShare]
    func recordID(for objectID: NSManagedObjectID) -> CKRecord.ID?
    /// Makes the object's ID permanent if needed and shares it in a new `CKShare`.
    func share(objectWith objectID: NSManagedObjectID) async throws -> CKShare
    func persistUpdatedShare(_ share: CKShare, in scope: PersistentStoreScope) async throws -> CKShare
    func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in scope: PersistentStoreScope) async throws
    func accountStatus() async throws -> CKAccountStatus
    func userRecordID() async throws -> CKRecord.ID
}

// MARK: - Share mutation path

extension CloudKitShareStoring {
    func fetchShare(for objectID: NSManagedObjectID) throws -> CKShare? {
        try fetchShares(matching: [objectID])[objectID]
    }

    /// The one path every share change is saved through. The deadline releases the caller even
    /// when the container never calls back; the save may still land later.
    func persistShare(
        _ share: CKShare,
        in scope: PersistentStoreScope,
        timeoutNanoseconds: UInt64 = FamilyInviteShareBudget.persistTimeoutNanoseconds
    ) async throws -> CKShare {
        try await CloudKitDeadline.run(timeoutNanoseconds: timeoutNanoseconds) {
            try await self.persistUpdatedShare(share, in: scope)
        }
    }

    /// The owner ACL heal and the invite door share this step: every non-owner participant gets
    /// read-write, the branding is stamped, and only `reopenInviteDoor` may turn a revoked door
    /// (`publicPermission = .none`) back to `.readWrite` (REQ-SHARE-060, REQ-SHARE-070). Returns
    /// the saved share, or nil when nothing changed and nothing was saved.
    func applyReadWriteACL(
        to share: CKShare,
        reopenInviteDoor: Bool,
        in scope: PersistentStoreScope
    ) async throws -> CKShare? {
        let aclChanged = OneCartShareLinkJoin.applyReadWriteACL(to: share, reopenInviteDoor: reopenInviteDoor)
        let brandingChanged = OneCartShareBranding.apply(to: share)
        guard aclChanged || brandingChanged else { return nil }
        CartSyncLog.shareACL.info(
            // swiftlint:disable:next line_length
            "share ACL persist reopenDoor=\(reopenInviteDoor, privacy: .public) aclChanged=\(aclChanged, privacy: .public) brandingChanged=\(brandingChanged, privacy: .public)"
        )
        return try await persistShare(share, in: scope)
    }
}

// MARK: - Live container

/// Creates the `CKContainer` on first use: constructing it in unit tests or on Xcode Cloud without
/// iCloud can crash.
final class LazyCloudContainer: Sendable {
    private let injected: CKContainer?
    private let cached = Mutex<CKContainer?>(nil)

    init(_ injected: CKContainer? = nil) {
        self.injected = injected
    }

    var container: CKContainer {
        if let injected {
            return injected
        }
        return cached.withLock { cached in
            if let cached {
                return cached
            }
            let created = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
            cached = created
            return created
        }
    }
}

struct LiveCloudKitShareStore: CloudKitShareStoring {
    let persistence: PersistenceController
    let cloudContainer: LazyCloudContainer

    init(persistence: PersistenceController, cloudContainer: LazyCloudContainer = LazyCloudContainer()) {
        self.persistence = persistence
        self.cloudContainer = cloudContainer
    }

    func fetchShares(matching objectIDs: [NSManagedObjectID]) throws -> [NSManagedObjectID: CKShare] {
        try persistence.container.fetchShares(matching: objectIDs)
    }

    func recordID(for objectID: NSManagedObjectID) -> CKRecord.ID? {
        persistence.container.recordID(for: objectID)
    }

    func share(objectWith objectID: NSManagedObjectID) async throws -> CKShare {
        let persistence = persistence
        return try await withCheckedThrowingContinuation { continuation in
            let context = persistence.newBackgroundContext(author: "OneCartShareCreate")
            context.perform {
                let object: NSManagedObject
                do {
                    object = try context.existingObject(with: objectID)
                    if object.objectID.isTemporaryID {
                        try context.obtainPermanentIDs(for: [object])
                        try context.save()
                    }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Resumed exactly once: a failure above returns before `share` is called, and the
                // container calls this completion once.
                persistence.container.share([object], to: nil) { _, share, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let share {
                        continuation.resume(returning: share)
                    } else {
                        continuation.resume(throwing: OneCartCloudKitError.shareURLUnavailable)
                    }
                }
            }
        }
    }

    func persistUpdatedShare(_ share: CKShare, in scope: PersistentStoreScope) async throws -> CKShare {
        let store = try persistence.store(for: scope)
        let container = persistence.container
        return try await withCheckedThrowingContinuation { continuation in
            container.persistUpdatedShare(share, in: store) { savedShare, error in
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

    func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in scope: PersistentStoreScope) async throws {
        let store = try persistence.store(for: scope)
        let container = persistence.container
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.purgeObjectsAndRecordsInZone(with: zoneID, in: store) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            cloudContainer.container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func userRecordID() async throws -> CKRecord.ID {
        try await cloudContainer.container.userRecordID()
    }
}
