import CoreData
import Foundation

/// Whether this participant may change one record; the repositories ask it before every write.
protocol PermissionAuthorizing: AnyObject, Sendable {
    func canUpdate(_ objectID: NSManagedObjectID) -> Bool
    func canDelete(_ objectID: NSManagedObjectID) -> Bool
}

/// The write guard every Core Data repository shares, so a denied write throws one error.
protocol PermissionGuardedRepository {
    var permissionAuthorizer: PermissionAuthorizing { get }
}

extension PermissionGuardedRepository {
    func requireUpdatePermission(for object: NSManagedObject) throws {
        guard permissionAuthorizer.canUpdate(object.objectID) else {
            throw RepositoryError.permissionDenied
        }
    }

    func requireDeletePermission(for object: NSManagedObject) throws {
        guard permissionAuthorizer.canDelete(object.objectID) else {
            throw RepositoryError.permissionDenied
        }
    }
}
