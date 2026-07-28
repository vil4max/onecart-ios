import CoreData
import Foundation
import OSLog

enum CartSyncLog {
    static let cart = Logger(subsystem: "com.vil555tim.onecart", category: "CartSync")
    static let shareACL = Logger(subsystem: "com.vil555tim.onecart", category: "ShareACL")
}

final class CloudKitPermissionAuthorizer: PermissionAuthorizing {
    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func canUpdate(_ objectID: NSManagedObjectID) -> Bool {
        guard !persistence.inMemory else { return true }
        guard persistence.scope(for: objectID) == .shared else { return true }
        let allowed = persistence.container.canUpdateRecord(forManagedObjectWith: objectID)
        if !allowed {
            CartSyncLog.cart.error("permission deny canUpdate entity=\(objectID.entity.name ?? "?", privacy: .public)")
        }
        return allowed
    }

    func canDelete(_ objectID: NSManagedObjectID) -> Bool {
        guard !persistence.inMemory else { return true }
        guard persistence.scope(for: objectID) == .shared else { return true }
        let allowed = persistence.container.canDeleteRecord(forManagedObjectWith: objectID)
        if !allowed {
            CartSyncLog.cart.error("permission deny canDelete entity=\(objectID.entity.name ?? "?", privacy: .public)")
        }
        return allowed
    }
}
