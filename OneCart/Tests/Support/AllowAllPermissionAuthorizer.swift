import CoreData
@testable import OneCart

/// Repository tests run on local-only stores, where no CloudKit share limits what a user may edit.
final class AllowAllPermissionAuthorizer: PermissionAuthorizing {
    func canUpdate(_: NSManagedObjectID) -> Bool {
        true
    }

    func canDelete(_: NSManagedObjectID) -> Bool {
        true
    }
}
