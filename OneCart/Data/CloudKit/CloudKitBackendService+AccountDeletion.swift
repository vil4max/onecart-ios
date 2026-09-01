import CloudKit
import Foundation

extension CloudKitBackendService {
    /// Permanently deletes deletable private-database record zones in the app container.
    /// Local Core Data CloudKit stores must already be unloaded so the mirror cannot recreate zones.
    func deletePrivateAccountCloudData() async throws {
        if persistence.inMemory || !persistence.cloudKitEnabled {
            return
        }

        let status = try await accountStatus()
        guard status == .available else {
            throw OneCartCloudKitError.accountUnavailable(status)
        }

        let database = cloudContainer.privateCloudDatabase
        let zones = try await database.allRecordZones()
        let zoneIDs = Self.recordZoneIDsForAccountDeletion(from: zones)
        guard !zoneIDs.isEmpty else {
            CartSyncLog.shareACL.info("deletePrivateAccountCloudData no deletable zones")
            return
        }

        CartSyncLog.shareACL.info(
            "deletePrivateAccountCloudData begin zones=\(zoneIDs.count)"
        )
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: zoneIDs)
            CartSyncLog.shareACL.info("deletePrivateAccountCloudData done")
        } catch {
            if Self.isIdempotentAccountDeletionFailure(error) {
                CartSyncLog.shareACL.info(
                    "deletePrivateAccountCloudData treat already-gone " +
                        "error=\(error.localizedDescription, privacy: .public)"
                )
                return
            }
            CartSyncLog.shareACL.error(
                "deletePrivateAccountCloudData fail error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    /// Skips the undeletable default zone; Core Data CloudKit data lives in custom zones.
    static func recordZoneIDsForAccountDeletion(from zones: [CKRecordZone]) -> [CKRecordZone.ID] {
        let defaultZoneID = CKRecordZone.default().zoneID
        return zones.map(\.zoneID).filter { $0 != defaultZoneID }
    }

    static func isIdempotentAccountDeletionFailure(_ error: Error) -> Bool {
        let failures = accountDeletionFailureLeaves(error)
        guard !failures.isEmpty else { return false }
        return failures.allSatisfy(isAlreadyDeletedZoneFailure)
    }

    private static func accountDeletionFailureLeaves(_ error: Error) -> [Error] {
        var result: [Error] = []
        var queue: [Error] = [error]
        var depth = 0
        while let current = queue.first, depth < 24 {
            queue.removeFirst()
            depth += 1
            let nsError = current as NSError
            if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error],
               !partial.isEmpty
            {
                queue.append(contentsOf: partial.values)
                continue
            }
            if let ckError = current as? CKError,
               let partial = ckError.partialErrorsByItemID,
               !partial.isEmpty
            {
                queue.append(contentsOf: partial.values)
                continue
            }
            result.append(current)
        }
        return result
    }

    private static func isAlreadyDeletedZoneFailure(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .zoneNotFound, .userDeletedZone, .unknownItem:
                return true
            default:
                break
            }
        }
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain {
            switch nsError.code {
            case CKError.Code.zoneNotFound.rawValue,
                 CKError.Code.userDeletedZone.rawValue,
                 CKError.Code.unknownItem.rawValue:
                return true
            default:
                break
            }
        }
        return false
    }
}
