import CoreData
import Foundation

/// Moves checked lines from the living cart into History (REQ-HIST-010).
protocol PurchaseArchiver: Sendable {
    /// Archives every checked line at once (demo and tests).
    @discardableResult
    func completePurchased(listID: UUID) async throws -> UUID?
    /// Archives the lines checked before `cutoff`; today's Completed lines stay on the cart.
    @discardableResult
    func archivePurchasedBefore(listID: UUID, cutoff: Date) async throws -> UUID?
}

final class CoreDataPurchaseArchiver: PurchaseArchiver, PermissionGuardedRepository, Sendable {
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing
    let clock: AppClock

    init(persistence: PersistenceController, permissionAuthorizer: PermissionAuthorizing, clock: AppClock) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
        self.clock = clock
    }

    @discardableResult
    func completePurchased(listID: UUID) async throws -> UUID? {
        try await archivePurchased(listID: listID, purchasedBefore: nil)
    }

    @discardableResult
    func archivePurchasedBefore(listID: UUID, cutoff: Date) async throws -> UUID? {
        try await archivePurchased(listID: listID, purchasedBefore: cutoff)
    }

    @discardableResult
    private func archivePurchased(listID: UUID, purchasedBefore cutoff: Date?) async throws -> UUID? {
        try await persistence.performBackgroundTask { context in
            guard let list = try RepositoryFetch.list(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            try self.requireUpdatePermission(for: list)
            guard let space = list.familySpace else {
                throw RepositoryError.familySpaceNotFound
            }

            let purchased = try Self.fetchPurchasedProducts(listID: listID, in: context).filter { product in
                guard let cutoff else { return true }
                // Edits move `updatedAt`, so a legacy check without `purchasedAt` dates by its
                // purchase version; otherwise every rename would postpone it another night.
                let purchasedAt = product.purchasedAt ?? product.purchaseVersion
                return purchasedAt < cutoff
            }
            guard !purchased.isEmpty else { return nil }

            let now = self.clock.now()
            let existingItems = try Self.existingHistoryItems(
                productIDs: purchased.compactMap(\.id),
                familySpace: space,
                in: context
            )
            var archivedIDs = Set(existingItems.compactMap(\.id))
            let unarchived = purchased.filter { product in
                guard let id = product.id else { return true }
                return archivedIDs.insert(id).inserted
            }
            for product in purchased {
                product.deletedAt = now
                product.updatedAt = now
            }
            list.updatedAt = now
            space.updatedAt = now

            guard !unarchived.isEmpty else {
                // A late product import must not recreate an already archived purchase.
                return existingItems.first?.history?.id
            }

            let historyID = UUID()
            let history = PurchaseHistoryEntity(context: context)
            try self.persistence.assign(history, toSameStoreAs: list, in: context)
            history.id = historyID
            history.date = now
            history.createdAt = now
            history.updatedAt = now
            history.familySpace = space
            history.store = list.store

            // The leftover per-line attributes are copied as stored, so a line an older build
            // wrote keeps its values in History; nothing here computes new ones.
            for product in unarchived {
                let item = HistoryItemEntity(context: context)
                try self.persistence.assign(item, toSameStoreAs: list, in: context)
                item.id = product.id ?? UUID()
                item.name = product.name
                item.quantity = product.quantity
                item.unit = product.unit
                item.category = product.category
                item.estimatedPrice = product.estimatedPrice
                item.originalPrice = product.originalPrice
                item.imageURL = product.imageURL
                item.sourceURL = product.sourceURL
                item.note = product.note
                item.purchasedAt = product.purchasedAt ?? now
                item.purchasedByName = product.purchasedByName
                item.createdByName = product.createdByName
                item.createdAt = product.createdAt
                item.updatedAt = now
                item.familySpace = space
                item.history = history
            }

            return historyID
        }
    }

    private static func fetchPurchasedProducts(
        listID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [ProductEntity] {
        let request = ProductEntity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "list.id == %@", listID as NSUUID),
            NSPredicate(format: "isPurchased == YES"),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.relationshipKeyPathsForPrefetching = ["list", "store"]
        return try context.fetch(request)
    }

    private static func existingHistoryItems(
        productIDs: [UUID],
        familySpace: FamilySpace,
        in context: NSManagedObjectContext
    ) throws -> [HistoryItemEntity] {
        guard !productIDs.isEmpty else { return [] }
        let request = HistoryItemEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "id IN %@", productIDs.map { $0 as NSUUID }),
            NSPredicate(format: "history.id != nil"),
        ]
        if let familyID = familySpace.id {
            predicates.append(NSPredicate(format: "familySpace.id == %@", familyID as NSUUID))
        } else {
            predicates.append(NSPredicate(format: "familySpace == %@", familySpace))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        if let store = familySpace.objectID.persistentStore {
            request.affectedStores = [store]
        }
        return try context.fetch(request)
    }
}
