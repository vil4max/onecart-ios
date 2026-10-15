import CoreData
@testable import OneCart

/// Shared-store records in tests have no CloudKit share to ask, so every edit is allowed.
struct AllowAllRecordPermissions: RecordPermissionChecking {
    func canUpdateRecord(forManagedObjectWith _: NSManagedObjectID) -> Bool {
        true
    }

    func canDeleteRecord(forManagedObjectWith _: NSManagedObjectID) -> Bool {
        true
    }
}
