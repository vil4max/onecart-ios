import CoreData
import Foundation

extension FamilySpaceRepository {
    func deduplicateStableIDs() async throws {
        try await persistence.performBackgroundTask(author: "OneCartDeduplication") { context in
            try Self.deduplicate(
                request: FamilySpace.fetchRequest(),
                familySpaceID: { $0.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try Self.deduplicate(
                request: StoreEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try Self.deduplicate(
                request: ShoppingListEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try Self.deduplicate(
                request: ProductEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try Self.deduplicate(
                request: PurchaseHistoryEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
        }
    }

    /// Merges living rows that share a normalized name within one list.
    /// Two devices can add «Молоко» / «молоко» concurrently with different
    /// stable IDs — CloudKit then delivers both records. First writer wins;
    /// losers become soft-delete tombstones so the merge propagates.
    /// - Returns: number of rows tombstoned.
    @discardableResult
    func deduplicateProductsByName() async throws -> Int {
        try await persistence.performBackgroundTask(author: "OneCartNameDedup") { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "deletedAt == nil")
            let products = try context.fetch(request)
            var groups: [String: [ProductEntity]] = [:]
            for product in products {
                guard let rawName = product.name else { continue }
                let normalized = FamilyCartMerge.normalizedProductName(rawName)
                guard !normalized.isEmpty else { continue }
                guard let storeIdentifier = product.objectID.persistentStore?.identifier else { continue }
                let listKey: String
                if let listID = product.list?.id {
                    listKey = "list:\(listID.uuidString)"
                } else if let familyID = product.familySpace?.id {
                    listKey = "family:\(familyID.uuidString)"
                } else {
                    continue
                }
                let key = "\(storeIdentifier)|\(listKey)|\(normalized)"
                groups[key, default: []].append(product)
            }
            var merged = 0
            let now = Date()
            for items in groups.values where items.count > 1 {
                let ordered = items.sorted {
                    let left = $0.createdAt ?? .distantPast
                    let right = $1.createdAt ?? .distantPast
                    if left != right {
                        return left < right
                    }
                    return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
                }
                for loser in ordered.dropFirst() where loser.deletedAt == nil {
                    loser.deletedAt = now
                    loser.updatedAt = now
                    merged += 1
                }
            }
            return merged
        }
    }

    static func deduplicate<T: NSManagedObject>(
        request: NSFetchRequest<T>,
        familySpaceID: (T) -> UUID?,
        stableID: (T) -> UUID?,
        updatedAt: (T) -> Date?,
        deletedAt: (T) -> Date? = { ($0 as? SoftDeletable)?.deletedAt },
        in context: NSManagedObjectContext
    ) throws {
        let objects = try context.fetch(request)
        var winners: [String: T] = [:]

        for object in objects {
            guard let stableID = stableID(object),
                  let storeIdentifier = object.objectID.persistentStore?.identifier
            else {
                continue
            }
            let familyID = familySpaceID(object)?.uuidString ?? "root"
            let key = "\(storeIdentifier)|\(familyID)|\(stableID.uuidString)"

            guard let winner = winners[key] else {
                winners[key] = object
                continue
            }

            let preferred = preferredDuplicate(
                existing: winner,
                candidate: object,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            )
            let loser = preferred === winner ? object : winner
            winners[key] = preferred
            // Soft-delete losers instead of hard-deleting mirrored CloudKit rows.
            if let softLoser = loser as? SoftDeletable, softLoser.deletedAt == nil {
                let now = Date()
                softLoser.deletedAt = now
                if let stamped = loser as? Timestamped {
                    stamped.updatedAt = now
                }
            } else if deletedAt(loser) == nil {
                context.delete(loser)
            }
        }
    }

    static func preferredDuplicate<T: NSManagedObject>(
        existing: T,
        candidate: T,
        updatedAt: (T) -> Date?,
        deletedAt: (T) -> Date?
    ) -> T {
        let existingDeleted = deletedAt(existing) != nil
        let candidateDeleted = deletedAt(candidate) != nil
        if existingDeleted != candidateDeleted {
            return candidateDeleted ? existing : candidate
        }
        let existingDate = updatedAt(existing) ?? .distantPast
        let candidateDate = updatedAt(candidate) ?? .distantPast
        return candidateDate > existingDate ? candidate : existing
    }
}
