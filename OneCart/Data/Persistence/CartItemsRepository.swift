import CoreData
import Foundation

/// Cart line mutations by stable ID: add, rename, category refinement, purchase state and delete.
protocol CartItemsRepository: Sendable {
    /// Adds a new cart line item. Idempotent by stable id (CloudKit redelivery)
    /// and by normalized name within the same list: if «Молоко» is already
    /// on the cart, adding «молоко» returns the existing row instead of
    /// creating a second line. Quantities are never summed — there is simply
    /// one shared row per name.
    @discardableResult
    func addProduct(to listID: UUID, id: UUID, draft: ProductDraft, createdByName: String?) async throws -> UUID
    func updateProduct(id: UUID, familySpaceID: UUID, draft: ProductDraft) async throws
    func updateProductCategory(id: UUID, familySpaceID: UUID, category: ProductCategory) async throws
    func setPurchasedState(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?
    ) async throws
    func setPurchased(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?,
        purchasedAt: Date
    ) async throws
    func deleteProduct(id: UUID, familySpaceID: UUID) async throws
}

final class CoreDataCartItemsRepository: CartItemsRepository, PermissionGuardedRepository, Sendable {
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing
    let clock: AppClock

    init(persistence: PersistenceController, permissionAuthorizer: PermissionAuthorizing, clock: AppClock) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
        self.clock = clock
    }

    @discardableResult
    func addProduct(
        to listID: UUID,
        id: UUID,
        draft: ProductDraft,
        createdByName: String?
    ) async throws -> UUID {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }
        let wantedKey = FamilyCartMerge.normalizedProductName(normalizedName)

        return try await persistence.performBackgroundTask { context in
            guard let list = try RepositoryFetch.list(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            try self.requireUpdatePermission(for: list)
            guard let space = list.familySpace else {
                throw RepositoryError.familySpaceNotFound
            }

            // Redelivery is idempotent only for the exact stable id, never by name; the name
            // check below is the duplicate-row product rule, not redelivery idempotency.
            if let existing = try RepositoryFetch.product(
                id: id,
                familySpaceID: space.id,
                in: context
            ) {
                return existing.id ?? id
            }

            // Duplicate protection: same normalized name in the same list
            // (case/whitespace/diacritic-insensitive) reuses the living row.
            // Deleted tombstones are ignored so a re-add after delete works.
            if let duplicate = try Self.fetchLiveProduct(
                normalizedName: wantedKey,
                listID: listID,
                in: context
            ), let duplicateID = duplicate.id {
                return duplicateID
            }

            let now = self.clock.now()
            let product = ProductEntity(context: context)
            try self.persistence.assign(product, toSameStoreAs: list, in: context)
            product.id = id
            Self.apply(draft: draft, to: product)
            product.isPurchased = false
            product.createdAt = now
            product.updatedAt = now
            product.purchasedAt = nil
            product.purchasedByName = nil
            product.createdByName = createdByName?.nilIfBlank
            product.familySpace = space
            product.list = list
            product.store = list.store
            list.updatedAt = now
            space.updatedAt = now
            return id
        }
    }

    func updateProduct(id: UUID, familySpaceID: UUID, draft: ProductDraft) async throws {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }
        let wantedKey = FamilyCartMerge.normalizedProductName(normalizedName)

        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: id, familySpaceID: familySpaceID, in: context)
            else {
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            let now = self.clock.now()
            // Rename into an existing living row merges instead of duplicating:
            // the edited duplicate is tombstoned, the earlier row stays visible.
            if let listID = product.list?.id,
                let collision = try Self.fetchLiveProduct(
                    normalizedName: wantedKey,
                    listID: listID,
                    excludingID: id,
                    in: context
                )
            {
                try self.requireDeletePermission(for: product)
                product.deletedAt = now
                product.updatedAt = now
                product.list?.updatedAt = now
                product.familySpace?.updatedAt = now
                return
            }
            // Like a category refinement, an edit keeps `updatedAt`, the purchase version
            // `setPurchased` compares queued widget commands against: renaming after a tap
            // must not make that tap look older than the row.
            Self.apply(draft: draft, to: product)
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    /// Writes only the category, so a background classification never touches the name or
    /// any other field a concurrent edit may have changed. The row's `updatedAt` is the purchase
    /// version `setPurchased` compares queued widget commands against; a classification that
    /// lands after a tap must not make that tap look older than the row, so it stays untouched.
    func updateProductCategory(id: UUID, familySpaceID: UUID, category: ProductCategory) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: id, familySpaceID: familySpaceID, in: context)
            else {
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            guard product.categoryValue != category else { return }
            let now = self.clock.now()
            product.category = category.rawValue
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    /// Applies the state the user asked for instead of flipping the stored one: when another
    /// shopper's change already reached the store, checking an item they checked keeps their
    /// check (and their name) rather than undoing it.
    func setPurchasedState(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?
    ) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: id, familySpaceID: familySpaceID, in: context)
            else {
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            guard product.isPurchasedValue != isPurchased else { return }
            let now = self.clock.now()
            product.isPurchased = NSNumber(value: isPurchased)
            product.purchasedAt = isPurchased ? now : nil
            product.purchasedByName =
                isPurchased
                ? participantDisplayName?.nilIfBlank
                : nil
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    func setPurchased(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?,
        purchasedAt: Date
    ) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: id, familySpaceID: familySpaceID, in: context)
            else {
                let tombstones = ProductEntity.fetchRequest()
                tombstones.predicate = NSPredicate(
                    format: "id == %@ AND familySpace.id == %@ AND deletedAt != nil",
                    id as NSUUID,
                    familySpaceID as NSUUID
                )
                tombstones.fetchLimit = 1
                if try context.fetch(tombstones).first != nil {
                    return
                }
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            // A retried command cannot replace a newer app edit or widget command.
            guard (product.updatedAt ?? .distantPast) < purchasedAt else { return }
            let now = self.clock.now()
            if product.isPurchasedValue != isPurchased {
                product.isPurchased = NSNumber(value: isPurchased)
                product.purchasedAt = isPurchased ? purchasedAt : nil
                product.purchasedByName = isPurchased ? participantDisplayName?.nilIfBlank : nil
            }
            product.updatedAt = purchasedAt
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    func deleteProduct(id: UUID, familySpaceID: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: id, familySpaceID: familySpaceID, in: context)
            else {
                throw RepositoryError.productNotFound
            }
            try self.requireDeletePermission(for: product)
            guard !product.isPurchasedValue else { return }
            let now = self.clock.now()
            product.deletedAt = now
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    private static func fetchLiveProduct(
        normalizedName: String,
        listID: UUID,
        excludingID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> ProductEntity? {
        guard !normalizedName.isEmpty else { return nil }
        let request = ProductEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "list.id == %@", listID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ]
        if let excludingID {
            predicates.append(NSPredicate(format: "id != %@", excludingID as NSUUID))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        // No fetch limit: normalization (case, whitespace, diacritics) cannot be expressed as a
        // predicate, so every live row of the list must be compared. Oldest first keeps the
        // first writer as the surviving row when several match.
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let candidates = try context.fetch(request)
        return candidates.first { candidate in
            guard let name = candidate.name else { return false }
            return FamilyCartMerge.normalizedProductName(name) == normalizedName
        }
    }

    private static func apply(draft: ProductDraft, to product: ProductEntity) {
        product.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        product.category = draft.category.rawValue
    }
}
