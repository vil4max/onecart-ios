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
    func addProduct(to listID: UUID, id: UUID, draft: ProductDraft, author: CartAuthor) async throws -> UUID
    func updateProduct(id: UUID, familySpaceID: UUID, draft: ProductDraft) async throws
    func updateProductCategory(id: UUID, familySpaceID: UUID, category: ProductCategory) async throws
    func setPurchasedState(id: UUID, familySpaceID: UUID, isPurchased: Bool, author: CartAuthor) async throws
    func setPurchased(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        author: CartAuthor,
        purchasedAt: Date
    ) async throws
    func deleteProduct(id: UUID, familySpaceID: UUID) async throws
}

/// Name-only entry points for callers that know no CloudKit identity (the repository facade the
/// tests seed through); the lines they write carry no author record name.
extension CartItemsRepository {
    @discardableResult
    func addProduct(to listID: UUID, id: UUID, draft: ProductDraft, createdByName: String?) async throws -> UUID {
        try await addProduct(to: listID, id: id, draft: draft, author: CartAuthor(displayName: createdByName))
    }

    func setPurchasedState(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?
    ) async throws {
        try await setPurchasedState(
            id: id,
            familySpaceID: familySpaceID,
            isPurchased: isPurchased,
            author: CartAuthor(displayName: participantDisplayName)
        )
    }

    func setPurchased(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?,
        purchasedAt: Date
    ) async throws {
        try await setPurchased(
            id: id,
            familySpaceID: familySpaceID,
            isPurchased: isPurchased,
            author: CartAuthor(displayName: participantDisplayName),
            purchasedAt: purchasedAt
        )
    }
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
        author: CartAuthor
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
            if let existingID = try Self.existingProductID(id: id, normalizedName: wantedKey, in: list) {
                return existingID
            }

            let now = self.clock.now()
            let product = ProductEntity(context: context)
            try self.persistence.assign(product, toSameStoreAs: list, in: context)
            product.id = id
            Self.apply(draft: draft, to: product)
            product.isPurchased = false
            product.createdAt = now
            // A new line starts its purchase version too, so a later edit can move `updatedAt`
            // without the row ever falling back to it.
            product.markPurchaseStateChanged(at: now)
            product.purchasedAt = nil
            product.purchasedByName = nil
            product.purchasedByRecordName = nil
            product.createdByName = author.displayName?.nilIfBlank
            product.createdByRecordName = author.recordName?.nilIfBlank
            product.familySpace = space
            product.list = list
            product.store = list.store
            list.updatedAt = now
            space.updatedAt = now
            return id
        }
    }

    /// The living row an add resolves to instead of inserting one, or nil for a new line.
    private static func existingProductID(
        id: UUID,
        normalizedName: String,
        in list: ShoppingListEntity
    ) throws -> UUID? {
        guard let context = list.managedObjectContext, let listID = list.id else { return nil }
        // Redelivery is idempotent only for the exact stable id, never by name; the name
        // check below is the duplicate-row product rule, not redelivery idempotency.
        if let existing = try RepositoryFetch.product(id: id, familySpaceID: list.familySpace?.id, in: context) {
            return existing.id ?? id
        }
        // Duplicate protection: same normalized name in the same list
        // (case/whitespace/diacritic-insensitive) reuses the living row.
        // Deleted tombstones are ignored so a re-add after delete works.
        return try fetchLiveProduct(normalizedName: normalizedName, listID: listID, in: context)?.id
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

// MARK: - Edits and delete

extension CoreDataCartItemsRepository {
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
            // The edit moves `updatedAt` for last-writer-wins merges; queued widget purchases
            // compare the separate purchase version, so a rename after a tap does not drop it.
            Self.apply(draft: draft, to: product)
            product.markEdited(at: now)
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    /// Writes only the category, so a background classification never touches the name or
    /// any other field a concurrent edit may have changed. Like a rename, it moves `updatedAt`
    /// and leaves the purchase version alone.
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
            product.markEdited(at: now)
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
}

// MARK: - Purchase state

extension CoreDataCartItemsRepository {
    /// Applies the state the user asked for instead of flipping the stored one: when another
    /// shopper's change already reached the store, checking an item they checked keeps their
    /// check (and their name) rather than undoing it.
    func setPurchasedState(id: UUID, familySpaceID: UUID, isPurchased: Bool, author: CartAuthor) async throws {
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
            Self.setBuyer(of: product, to: isPurchased ? author : nil)
            product.markPurchaseStateChanged(at: now)
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    func setPurchased(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        author: CartAuthor,
        purchasedAt: Date
    ) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: id, familySpaceID: familySpaceID, in: context)
            else {
                if try Self.hasTombstone(id: id, familySpaceID: familySpaceID, in: context) {
                    return
                }
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            // A retried command cannot replace a newer purchase-state change from the app or
            // another widget command; edits move only `updatedAt` and never block it.
            guard product.purchaseVersion < purchasedAt else { return }
            // The version is the command's own time, not now: commands queued for one line
            // replay in order, and each must still be newer than the one applied before it.
            product.purchaseUpdatedAt = purchasedAt
            // A command the row already matches changes nothing a merge should see: moving
            // `updatedAt` would make it look like the newest edit and win LWW over a later one.
            guard product.isPurchasedValue != isPurchased else { return }
            let now = self.clock.now()
            product.isPurchased = NSNumber(value: isPurchased)
            product.purchasedAt = isPurchased ? purchasedAt : nil
            Self.setBuyer(of: product, to: isPurchased ? author : nil)
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    /// Credits a check to its author by name and CloudKit identity; nil clears both on uncheck.
    private static func setBuyer(of product: ProductEntity, to author: CartAuthor?) {
        product.purchasedByName = author?.displayName?.nilIfBlank
        product.purchasedByRecordName = author?.recordName?.nilIfBlank
    }

    private static func hasTombstone(
        id: UUID,
        familySpaceID: UUID,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        let tombstones = ProductEntity.fetchRequest()
        tombstones.predicate = NSPredicate(
            format: "id == %@ AND familySpace.id == %@ AND deletedAt != nil",
            id as NSUUID,
            familySpaceID as NSUUID
        )
        tombstones.fetchLimit = 1
        return try context.fetch(tombstones).first != nil
    }
}
