import CoreData
import Foundation

extension FamilySpaceRepository {
    func restoreProvisionalPersonalContent(
        from sourceID: UUID,
        into destinationID: UUID,
        accountID: UUID
    ) async throws -> Bool {
        guard sourceID != destinationID else { return true }
        return try await persistence.performBackgroundTask(author: "OneCartPersonalRestore") { context in
            let source = try Self.requireFamilySpace(id: sourceID, in: context)
            let destination = try Self.requireFamilySpace(id: destinationID, in: context)
            guard self.persistence.scope(for: source) == .private,
                  self.persistence.scope(for: destination) == .private
            else { throw RepositoryError.crossShareRelationship }
            guard source.cachedForUserID == accountID, destination.cachedForUserID == accountID else {
                throw RepositoryError.permissionDenied
            }
            try self.requireUpdatePermission(for: destination)
            guard let targetList = destination.activeLists.first, targetList.id != nil else { return false }

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
                var destinations = Dictionary(grouping: batch.destination) { $0.value(forKey: "id") as? UUID }
                for object in batch.source {
                    guard let id = object.value(forKey: "id") as? UUID else { continue }
                    let existing = destinations[id]?.sorted(by: Self.preferRestoreObject).first
                    let copy: NSManagedObject
                    if let existing {
                        copy = existing
                    } else {
                        copy = NSEntityDescription.insertNewObject(forEntityName: batch.entityName, into: context)
                        try self.persistence.assign(copy, toSameStoreAs: destination, in: context)
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

    private static func shouldRestoreAttributes(from source: NSManagedObject,
                                                onto destination: NSManagedObject) -> Bool
    {
        // Tombstones are absorbing: a retry must not revive a destination deletion.
        guard destination.value(forKey: "deletedAt") == nil else { return false }
        if source.value(forKey: "deletedAt") != nil {
            return true
        }
        let sourceUpdated = source.value(forKey: "updatedAt") as? Date ?? .distantPast
        let destinationUpdated = destination.value(forKey: "updatedAt") as? Date ?? .distantPast
        return sourceUpdated > destinationUpdated
    }

    func mergeFamilyContent(
        from sourceID: UUID,
        into destinationID: UUID,
        archiveSource: Bool = true
    ) async throws {
        try await persistence.performBackgroundTask(author: "OneCartFamilyMerge") { context in
            let source = try Self.requireFamilySpace(id: sourceID, in: context)
            let destination = try Self.requireFamilySpace(id: destinationID, in: context)
            guard self.persistence.scope(for: source.objectID) == .private else {
                throw RepositoryError.crossShareRelationship
            }
            try self.requireUpdatePermission(for: destination)

            let destinationList = destination.activeLists.first
                ?? destination.sortedLists.first
            guard let targetList = destinationList, targetList.id != nil else {
                throw RepositoryError.listNotFound
            }

            var storeMap: [UUID: StoreEntity] = [:]
            for store in destination.sortedStores {
                if let storeID = store.id {
                    storeMap[storeID] = store
                }
            }

            let now = Date()
            for store in source.sortedStores {
                let copied = StoreEntity(context: context)
                try self.persistence.assign(copied, toSameStoreAs: destination, in: context)
                let newStoreID = UUID()
                copied.id = newStoreID
                copied.name = store.name
                copied.icon = store.icon
                copied.colorHex = store.colorHex
                copied.address = store.address
                copied.latitude = store.latitude
                copied.longitude = store.longitude
                copied.externalAppURL = store.externalAppURL
                copied.isPinned = store.isPinned
                copied.createdAt = store.createdAt ?? now
                copied.updatedAt = now
                copied.familySpace = destination
                if let sourceStoreID = store.id {
                    storeMap[sourceStoreID] = copied
                }
            }

            var destinationByName: [String: ProductEntity] = [:]
            for product in destination.sortedProducts {
                let key = FamilyCartMerge.normalizedProductName(product.displayName)
                guard !key.isEmpty else { continue }
                if let existing = destinationByName[key] {
                    let preferNew = FamilyCartMerge.shouldPreferSourceProduct(
                        sourceUpdatedAt: product.updatedAt,
                        destinationUpdatedAt: existing.updatedAt
                    )
                    if preferNew {
                        destinationByName[key] = product
                    }
                } else {
                    destinationByName[key] = product
                }
            }

            for product in source.sortedProducts {
                let key = FamilyCartMerge.normalizedProductName(product.displayName)
                if let existing = destinationByName[key],
                   FamilyCartMerge.shouldPreferSourceProduct(
                       sourceUpdatedAt: product.updatedAt,
                       destinationUpdatedAt: existing.updatedAt
                   )
                {
                    Self.applyProductFields(from: product, onto: existing, now: now)
                    if let storeID = product.store?.id {
                        existing.store = storeMap[storeID]
                    }
                    existing.list = targetList
                    existing.updatedAt = product.updatedAt ?? now
                    continue
                }

                if destinationByName[key] != nil {
                    continue
                }

                let copied = ProductEntity(context: context)
                try self.persistence.assign(copied, toSameStoreAs: destination, in: context)
                copied.id = UUID()
                Self.applyProductFields(from: product, onto: copied, now: now)
                copied.createdAt = product.createdAt ?? now
                copied.updatedAt = product.updatedAt ?? now
                copied.familySpace = destination
                copied.list = targetList
                if let storeID = product.store?.id {
                    copied.store = storeMap[storeID]
                }
                if !key.isEmpty {
                    destinationByName[key] = copied
                }
            }

            destination.updatedAt = now
            targetList.updatedAt = now
        }
        if archiveSource {
            try await archiveFamilySpace(id: sourceID)
        }
    }

    private static func applyProductFields(
        from source: ProductEntity,
        onto destination: ProductEntity,
        now: Date
    ) {
        destination.name = source.name
        destination.quantity = source.quantity
        destination.unit = source.unit
        destination.category = source.category
        destination.estimatedPrice = source.estimatedPrice
        destination.originalPrice = source.originalPrice
        destination.loyaltyPrice = source.loyaltyPrice
        destination.note = source.note
        destination.imageURL = source.imageURL
        destination.sourceURL = source.sourceURL
        destination.catalogFetchedAt = source.catalogFetchedAt
        destination.promotionEndsAt = source.promotionEndsAt
        destination.isPurchased = source.isPurchased
        destination.purchasedAt = source.purchasedAt
        destination.purchasedByName = source.purchasedByName
        destination.createdByName = source.createdByName
        if destination.createdAt == nil {
            destination.createdAt = source.createdAt ?? now
        }
    }
}
