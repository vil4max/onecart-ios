import CoreData
import Foundation

/// What the current iCloud user may do to one shared-store record, as the CloudKit share says.
protocol RecordPermissionChecking: Sendable {
    func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool
    func canDeleteRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool
}

/// Asks the persistence container, which reads the participant's permission on the record's share.
struct ContainerRecordPermissions: RecordPermissionChecking {
    let persistence: PersistenceController

    func canUpdateRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool {
        persistence.container.canUpdateRecord(forManagedObjectWith: objectID)
    }

    func canDeleteRecord(forManagedObjectWith objectID: NSManagedObjectID) -> Bool {
        persistence.container.canDeleteRecord(forManagedObjectWith: objectID)
    }
}
