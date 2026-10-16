import CoreData
import Foundation

/// Copies a provisional personal cart into an older personal cart of the same account that
/// arrived late from iCloud, by stable IDs (REQ-SYNC-040).
protocol PersonalCartRestorer: Sendable {
    /// - Returns: whether the destination now holds the source's content; false when the
    ///   source graph is still incomplete or the destination has no list yet.
    func restoreProvisionalPersonalContent(
        from sourceID: UUID,
        into destinationID: UUID,
        accountID: UUID
    ) async throws -> Bool
}

final class CoreDataPersonalCartRestorer: PersonalCartRestorer, PermissionGuardedRepository, Sendable {
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing

    init(persistence: PersistenceController, permissionAuthorizer: PermissionAuthorizing) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
    }

    func restoreProvisionalPersonalContent(
        from sourceID: UUID,
        into destinationID: UUID,
        accountID: UUID
    ) async throws -> Bool {
        guard sourceID != destinationID else { return true }
        return try await persistence.performBackgroundTask(author: "OneCartPersonalRestore") { context in
            let source = try RepositoryFetch.requireFamilySpace(id: sourceID, in: context)
            let destination = try RepositoryFetch.requireFamilySpace(id: destinationID, in: context)
            guard self.persistence.scope(for: source) == .private,
                self.persistence.scope(for: destination) == .private
            else { throw RepositoryError.crossShareRelationship }
            guard source.cachedForUserID == accountID, destination.cachedForUserID == accountID else {
                throw RepositoryError.permissionDenied
            }
            try self.requireUpdatePermission(for: destination)
            guard let targetList = ShoppingListEntity.primaryList(in: destination.activeLists), targetList.id != nil
            else { return false }

            let batches = try ["Store", "Product", "PurchaseHistory", "HistoryItem"].map { entityName in
                try PersonalRestoreBatch(
                    entityName: entityName,
                    source: Self.restoreObjects(entityName: entityName, family: source, in: context),
                    destination: Self.restoreObjects(entityName: entityName, family: destination, in: context)
                )
            }
            guard Self.isCompleteRestoreGraph(batches.flatMap(\.source)) else { return false }

            var restoredObjects: [NSManagedObjectID: NSManagedObject] = [:]
            var changedObjects: [(source: NSManagedObject, destination: NSManagedObject)] = []
            for batch in batches {
                try self.copyRestoreBatch(
                    batch,
                    into: destination,
                    context: context,
                    restoredObjects: &restoredObjects,
                    changedObjects: &changedObjects
                )
            }
            for (object, copy) in changedObjects {
                copy.setValue(destination, forKey: "familySpace")
                if copy is ProductEntity {
                    copy.setValue(targetList, forKey: "list")
                }
                for key in ["store", "history"] where object.entity.relationshipsByName[key] != nil {
                    let related = object.value(forKey: key) as? NSManagedObject
                    copy.setValue(related.flatMap { restoredObjects[$0.objectID] }, forKey: key)
                }
            }
            return true
        }
    }

    private struct PersonalRestoreBatch {
        let entityName: String
        let source: [NSManagedObject]
        let destination: [NSManagedObject]
    }

    /// Reuses a destination row with the same id, or inserts a copy in the destination's store.
    private func copyRestoreBatch(
        _ batch: PersonalRestoreBatch,
        into destination: FamilySpace,
        context: NSManagedObjectContext,
        restoredObjects: inout [NSManagedObjectID: NSManagedObject],
        changedObjects: inout [(source: NSManagedObject, destination: NSManagedObject)]
    ) throws {
        var destinations = Dictionary(grouping: batch.destination) { $0.value(forKey: "id") as? UUID }
        for object in batch.source {
            guard let id = object.value(forKey: "id") as? UUID else { continue }
            let existing = destinations[id]?.sorted(by: Self.preferRestoreObject).first
            let copy: NSManagedObject
            if let existing {
                copy = existing
            } else {
                copy = NSEntityDescription.insertNewObject(forEntityName: batch.entityName, into: context)
                try persistence.assign(copy, toSameStoreAs: destination, in: context)
                destinations[id] = [copy]
            }
            restoredObjects[object.objectID] = copy
            guard existing == nil || Self.shouldRestoreAttributes(from: object, onto: copy) else { continue }
            for key in object.entity.attributesByName.keys {
                copy.setValue(object.value(forKey: key), forKey: key)
            }
            changedObjects.append((object, copy))
        }
    }

    private static func restoreObjects(
        entityName: String,
        family: FamilySpace,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "familySpace == %@", family)
        return try context.fetch(request)
    }

    private static func isCompleteRestoreGraph(_ objects: [NSManagedObject]) -> Bool {
        let objectIDs = Set(objects.map(\.objectID))
        return objects.allSatisfy { object in
            guard object.value(forKey: "id") is UUID else { return false }
            if let item = object as? HistoryItemEntity, item.history == nil {
                return false
            }
            return ["store", "history"].allSatisfy { key in
                guard object.entity.relationshipsByName[key] != nil,
                    let related = object.value(forKey: key) as? NSManagedObject
                else { return true }
                return objectIDs.contains(related.objectID)
            }
        }
    }

    private static func preferRestoreObject(_ lhs: NSManagedObject, _ rhs: NSManagedObject) -> Bool {
        let leftDeleted = lhs.value(forKey: "deletedAt") as? Date
        let rightDeleted = rhs.value(forKey: "deletedAt") as? Date
        if (leftDeleted != nil) != (rightDeleted != nil) {
            return leftDeleted != nil
        }
        let leftUpdated = lhs.value(forKey: "updatedAt") as? Date ?? .distantPast
        let rightUpdated = rhs.value(forKey: "updatedAt") as? Date ?? .distantPast
        return leftUpdated > rightUpdated
    }

    private static func shouldRestoreAttributes(
        from source: NSManagedObject,
        onto destination: NSManagedObject
    ) -> Bool {
        // Tombstones are absorbing: a retry must not revive a destination deletion.
        guard destination.value(forKey: "deletedAt") == nil else { return false }
        if source.value(forKey: "deletedAt") != nil {
            return true
        }
        // Every edit moves updatedAt, so a retry carries one made on the provisional cart since
        // the last copy and keeps a newer destination edit; a tie keeps the destination too.
        let sourceUpdated = source.value(forKey: "updatedAt") as? Date ?? .distantPast
        let destinationUpdated = destination.value(forKey: "updatedAt") as? Date ?? .distantPast
        return sourceUpdated > destinationUpdated
    }
}
