import CoreData
import Foundation

/// Private-store records always belong to this user; only a shared-store record asks the share.
final class CloudKitPermissionAuthorizer: PermissionAuthorizing {
    private let persistence: PersistenceController
    private let permissions: any RecordPermissionChecking

    init(persistence: PersistenceController, permissions: any RecordPermissionChecking) {
        self.persistence = persistence
        self.permissions = permissions
    }

    func canUpdate(_ objectID: NSManagedObjectID) -> Bool {
        guard persistence.scope(for: objectID) == .shared else { return true }
        let allowed = permissions.canUpdateRecord(forManagedObjectWith: objectID)
        if !allowed {
            CartSyncLog.cart.error("permission deny canUpdate entity=\(objectID.entity.name ?? "?", privacy: .public)")
        }
        return allowed
    }

    func canDelete(_ objectID: NSManagedObjectID) -> Bool {
        guard persistence.scope(for: objectID) == .shared else { return true }
        let allowed = permissions.canDeleteRecord(forManagedObjectWith: objectID)
        if !allowed {
            CartSyncLog.cart.error("permission deny canDelete entity=\(objectID.entity.name ?? "?", privacy: .public)")
        }
        return allowed
    }
}
