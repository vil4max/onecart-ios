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
