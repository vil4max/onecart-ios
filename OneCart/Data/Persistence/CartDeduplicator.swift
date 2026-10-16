import CoreData
import Foundation

/// Launch and sync dedupe of replica rows: one living row per stable ID, and per normalized
/// name within one list.
protocol CartDeduplicator: Sendable {
    func deduplicateStableIDs() async throws
    /// - Returns: number of rows tombstoned.
    @discardableResult
    func deduplicateProductsByName() async throws -> Int
}

final class CoreDataCartDeduplicator: CartDeduplicator, Sendable {
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing
    let clock: AppClock

    init(persistence: PersistenceController, permissionAuthorizer: PermissionAuthorizing, clock: AppClock) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
        self.clock = clock
    }

    func deduplicateStableIDs() async throws {
        try await persistence.performBackgroundTask(author: "OneCartDeduplication") { context in
            try self.deduplicate(
                request: FamilySpace.fetchRequest(),
                familySpaceID: { $0.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try self.deduplicate(
                request: StoreEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try self.deduplicate(
                request: ShoppingListEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try self.deduplicate(
                request: ProductEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try self.deduplicate(
                request: PurchaseHistoryEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
            try self.deduplicate(
                request: MemberProfileEntity.fetchRequest(),
                familySpaceID: { $0.familySpace?.id },
                stableID: { $0.id },
                updatedAt: { $0.updatedAt },
                in: context
            )
        }
    }

    private func deduplicate<T: NSManagedObject>(
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

            let preferred = Self.preferredDuplicate(
                existing: winner,
                candidate: object,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            )
            let loser = preferred === winner ? object : winner
            winners[key] = preferred
            // Soft-delete losers instead of hard-deleting mirrored CloudKit rows.
            if let softLoser = loser as? SoftDeletable, softLoser.deletedAt == nil {
                let deletedNow = clock.now()
                softLoser.deletedAt = deletedNow
                if let stamped = loser as? Timestamped {
                    stamped.updatedAt = deletedNow
                }
            } else if deletedAt(loser) == nil {
                context.delete(loser)
            }
        }
    }

    private static func preferredDuplicate<T: NSManagedObject>(
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
        if candidateDate != existingDate {
            return candidateDate > existingDate ? candidate : existing
        }
        // Replicas of one write carry the same updatedAt; fetch order must not pick the survivor.
        let existingKey = existing.objectID.uriRepresentation().absoluteString
        let candidateKey = candidate.objectID.uriRepresentation().absoluteString
        return candidateKey < existingKey ? candidate : existing
    }
}

// MARK: - Same name within one list

extension CoreDataCartDeduplicator {
    /// Merges living rows that share a normalized name within one list.
    /// Two devices can add «Молоко» / «молоко» concurrently with different
    /// stable IDs — CloudKit then delivers both records. First writer wins and
    /// inherits a loser's purchase state; losers become soft-delete tombstones so
    /// the merge propagates. Groups the participant may not update are skipped.
    @discardableResult
    func deduplicateProductsByName() async throws -> Int {
        try await persistence.performBackgroundTask(author: "OneCartNameDedup") { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "deletedAt == nil")
            let products = try context.fetch(request)
            var groups: [String: [ProductEntity]] = [:]
            for product in products {
                guard let key = Self.nameDedupKey(for: product) else { continue }
                groups[key, default: []].append(product)
            }
            var merged = 0
            let now = self.clock.now()
            for items in groups.values where items.count > 1 {
                let ordered = items.sorted(by: Self.isWrittenFirst)
                // Read-only participants cannot export these writes; leave the merge to a writer's device.
                guard let winner = ordered.first,
                    ordered.allSatisfy({ self.permissionAuthorizer.canUpdate($0.objectID) })
                else {
                    continue
                }
                Self.inheritLatestPurchase(into: winner, from: ordered.dropFirst(), now: now)
                for loser in ordered.dropFirst() where loser.deletedAt == nil {
                    loser.deletedAt = now
                    loser.updatedAt = now
                    merged += 1
                }
            }
            return merged
        }
    }

    /// Oldest first, then by stable ID, so every device picks the same first writer.
    private static func isWrittenFirst(_ lhs: ProductEntity, _ rhs: ProductEntity) -> Bool {
        let left = lhs.createdAt ?? .distantPast
        let right = rhs.createdAt ?? .distantPast
        if left != right {
            return left < right
        }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }

    /// A loser may carry the only Completed tick (checked off on another device).
    private static func inheritLatestPurchase(
        into winner: ProductEntity,
        from losers: ArraySlice<ProductEntity>,
        now: Date
    ) {
        let latestPurchase =
            losers
            .filter(\.isPurchasedValue)
            .max { ($0.purchasedAt ?? .distantPast) < ($1.purchasedAt ?? .distantPast) }
        guard !winner.isPurchasedValue, let latestPurchase else { return }
        winner.isPurchased = NSNumber(value: true)
        winner.purchasedAt = latestPurchase.purchasedAt ?? now
        winner.purchasedByName = latestPurchase.purchasedByName
        winner.markPurchaseStateChanged(at: now)
    }

    /// Rows collide only inside one store and one list (or one family when the list is gone).
    private static func nameDedupKey(for product: ProductEntity) -> String? {
        guard let rawName = product.name else { return nil }
        let normalized = FamilyCartMerge.normalizedProductName(rawName)
        guard !normalized.isEmpty,
            let storeIdentifier = product.objectID.persistentStore?.identifier
        else { return nil }
        let listKey: String
        if let listID = product.list?.id {
            listKey = "list:\(listID.uuidString)"
        } else if let familyID = product.familySpace?.id {
            listKey = "family:\(familyID.uuidString)"
        } else {
            return nil
        }
        return "\(storeIdentifier)|\(listKey)|\(normalized)"
    }
}
