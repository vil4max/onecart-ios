import CoreData
import Foundation

protocol PermissionAuthorizing: AnyObject {
    func canUpdate(_ objectID: NSManagedObjectID) -> Bool
    func canDelete(_ objectID: NSManagedObjectID) -> Bool
}

final class AllowAllPermissionAuthorizer: PermissionAuthorizing {
    func canUpdate(_: NSManagedObjectID) -> Bool {
        true
    }

    func canDelete(_: NSManagedObjectID) -> Bool {
        true
    }
}

enum RepositoryError: LocalizedError, Equatable {
    case familySpaceNotFound
    case listNotFound
    case productNotFound
    case storeNotFound
    case permissionDenied
    case crossShareRelationship
    case invalidName

    var errorDescription: String? {
        switch self {
        case .familySpaceNotFound:
            "Группа не найдена."
        case .listNotFound:
            "Список покупок не найден."
        case .productNotFound:
            "Товар не найден."
        case .storeNotFound:
            "Магазин не найден."
        case .permissionDenied:
            "У вас нет права изменять эту корзину."
        case .crossShareRelationship:
            "Нельзя связывать данные из разных корзин."
        case .invalidName:
            "Введите название."
        }
    }
}

struct ProductDraft: Equatable {
    var name: String
    var quantity: Double
    var unit: ProductUnit
    var category: ProductCategory
    var estimatedPrice: Double
    var note: String
    var imageURL: String?
    var sourceURL: String?
    var originalPrice: Double?
    var loyaltyPrice: Double?
    var catalogFetchedAt: Date?
    var promotionEndsAt: Date?
}

final class FamilySpaceRepository {
    private let persistence: PersistenceController
    private let permissionAuthorizer: PermissionAuthorizing

    init(
        persistence: PersistenceController,
        permissionAuthorizer: PermissionAuthorizing
    ) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
    }

    func fetchFamilySpaces(for userID: UUID? = nil) throws -> [FamilySpace] {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSPredicate(format: "deletedAt == nil")
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
        ]
        let spaces = try persistence.container.viewContext.fetch(request)
        guard let userID else { return spaces }
        // Private carts are scoped to the SIWA-derived account. Shared-store carts
        // belong to the device iCloud share participant and stay visible.
        return spaces.filter { space in
            if persistence.scope(for: space) == .shared {
                return true
            }
            return space.cachedForUserID == userID
        }
    }

    func fetchFamilySpace(id: UUID) throws -> FamilySpace? {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.fetchLimit = 1
        return try persistence.container.viewContext.fetch(request).first
    }

    func createFamilySpace(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        cachedForUserID: UUID? = nil,
        serverRole: String? = nil,
        needsRemoteCreation: Bool = false,
        isHouseholdDefault: Bool = false
    ) async throws -> UUID {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }

        return try await persistence.performBackgroundTask { context in
            if let existing = try Self.fetchFamilySpace(id: id, in: context) {
                return existing.id ?? id
            }

            let space = FamilySpace(context: context)
            try self.persistence.assign(space, to: .private, in: context)
            space.id = id
            space.name = normalizedName
            space.createdAt = createdAt
            space.updatedAt = createdAt
            space.cachedForUserID = cachedForUserID
            space.serverRole = serverRole
            space.needsRemoteCreation = NSNumber(value: needsRemoteCreation)
            space.isHouseholdDefault = NSNumber(value: isHouseholdDefault)

            let list = ShoppingListEntity(context: context)
            try self.persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = UUID()
            list.title = "Общий список"
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = createdAt
            list.updatedAt = createdAt
            list.familySpace = space

            return id
        }
    }

    func migrateLegacyHouseholdDefaultsIfNeeded() async throws {
        try await persistence.performBackgroundTask(author: "OneCartHouseholdDefaultMigration") { context in
            let request = FamilySpace.fetchRequest()
            request.predicate = NSPredicate(format: "deletedAt == nil")
            let spaces = try context.fetch(request)
            var changed = false
            for space in spaces {
                if space.isHouseholdDefaultValue { continue }
                let name = space.name ?? ""
                if FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault(name) {
                    space.isHouseholdDefault = NSNumber(value: true)
                    space.updatedAt = Date()
                    changed = true
                }
            }
            if !changed {
                context.rollback()
            }
        }
    }

    func claimUnassignedFamilySpaces(for userID: UUID) async throws {
        try await persistence.performBackgroundTask(author: "OneCartAccountClaim") { context in
            let request = FamilySpace.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "cachedForUserID == nil"),
                NSPredicate(format: "deletedAt == nil"),
            ])
            let spaces = try context.fetch(request)
            for space in spaces {
                // Never stamp owner cache metadata onto shared-store records.
                guard self.persistence.scope(for: space) != .shared else { continue }
                space.cachedForUserID = userID
                space.serverRole = "owner"
                space.needsRemoteCreation = false
            }
        }
    }

    func associateFamilySpace(
        id: UUID,
        with userID: UUID,
        role: String,
        needsRemoteCreation: Bool
    ) async throws {
        try await persistence.performBackgroundTask(author: "OneCartFamilyAssociation") { context in
            let space = try Self.requireFamilySpace(id: id, in: context)
            space.cachedForUserID = userID
            space.serverRole = role
            space.needsRemoteCreation = NSNumber(value: needsRemoteCreation)
        }
    }

    func removeCachedFamilySpace(id: UUID, for userID: UUID) async throws {
        try await persistence.performBackgroundTask(author: "OneCartCacheCleanup") { context in
            let request = FamilySpace.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", id as NSUUID),
                NSPredicate(format: "cachedForUserID == %@", userID as NSUUID),
            ])
            for space in try context.fetch(request) {
                context.delete(space)
            }
        }
    }

    func renameFamilySpace(id: UUID, name: String) async throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }

        try await persistence.performBackgroundTask { context in
            let space = try Self.requireFamilySpace(id: id, in: context)
            try self.requireUpdatePermission(for: space)
            space.name = normalizedName
            space.updatedAt = Date()
        }
    }

    func archiveFamilySpace(id: UUID) async throws {
        try await persistence.performBackgroundTask(author: "OneCartFamilyArchive") { context in
            let space = try Self.requireFamilySpace(id: id, in: context)
            let now = Date()
            for product in (space.products?.allObjects as? [ProductEntity] ?? []) where product.deletedAt == nil {
                product.deletedAt = now
                product.updatedAt = now
            }
            for list in (space.lists?.allObjects as? [ShoppingListEntity] ?? []) where list.deletedAt == nil {
                list.deletedAt = now
                list.updatedAt = now
            }
            for store in (space.stores?.allObjects as? [StoreEntity] ?? []) where store.deletedAt == nil {
                store.deletedAt = now
                store.updatedAt = now
            }
            for entry in (space.historyEntries?.allObjects as? [PurchaseHistoryEntity] ?? [])
                where entry.deletedAt == nil
            {
                entry.deletedAt = now
                entry.updatedAt = now
            }
            space.deletedAt = now
            space.updatedAt = now
        }
    }

    func mergeFamilyContent(from sourceID: UUID, into destinationID: UUID) async throws {
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

            for product in source.sortedProducts {
                let copied = ProductEntity(context: context)
                try self.persistence.assign(copied, toSameStoreAs: destination, in: context)
                copied.id = UUID()
                copied.name = product.name
                copied.quantity = product.quantity
                copied.unit = product.unit
                copied.category = product.category
                copied.estimatedPrice = product.estimatedPrice
                copied.originalPrice = product.originalPrice
                copied.loyaltyPrice = product.loyaltyPrice
                copied.note = product.note
                copied.imageURL = product.imageURL
                copied.sourceURL = product.sourceURL
                copied.catalogFetchedAt = product.catalogFetchedAt
                copied.promotionEndsAt = product.promotionEndsAt
                copied.isPurchased = product.isPurchased
                copied.purchasedAt = product.purchasedAt
                copied.purchasedByName = product.purchasedByName
                copied.createdAt = product.createdAt ?? now
                copied.updatedAt = now
                copied.familySpace = destination
                copied.list = targetList
                if let storeID = product.store?.id {
                    copied.store = storeMap[storeID]
                }
            }

            destination.updatedAt = now
            targetList.updatedAt = now
        }
        try await archiveFamilySpace(id: sourceID)
    }

    /// Adds a new cart line item. Same name / catalog URL as an existing row still
    /// creates a separate unique position — quantities are never summed across members.
    @discardableResult
    func addProduct(
        to listID: UUID,
        id: UUID = UUID(),
        draft: ProductDraft,
        purchasedByName: String? = nil
    ) async throws -> UUID {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }

        return try await persistence.performBackgroundTask { context in
            guard let list = try Self.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            try self.requireUpdatePermission(for: list)
            guard let space = list.familySpace else {
                throw RepositoryError.familySpaceNotFound
            }

            // Idempotent only for the exact stable id (CloudKit redelivery), never by name.
            if let existing = try Self.fetchProduct(
                id: id,
                familySpaceID: space.id,
                in: context
            ) {
                return existing.id ?? id
            }

            let now = Date()
            let product = ProductEntity(context: context)
            try self.persistence.assign(product, toSameStoreAs: list, in: context)
            product.id = id
            Self.apply(draft: draft, to: product)
            product.isPurchased = false
            product.createdAt = now
            product.updatedAt = now
            product.purchasedAt = nil
            product.purchasedByName = purchasedByName?.trimmedNilIfEmpty
            product.familySpace = space
            product.list = list
            product.store = list.store
            list.updatedAt = now
            space.updatedAt = now
            return id
        }
    }

    func updateProduct(id: UUID, draft: ProductDraft) async throws {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }

        try await persistence.performBackgroundTask { context in
            guard let product = try Self.fetchProduct(id: id, in: context) else {
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            let now = Date()
            Self.apply(draft: draft, to: product)
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    func togglePurchased(
        id: UUID,
        participantDisplayName: String?
    ) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try Self.fetchProduct(id: id, in: context) else {
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            let now = Date()
            let nextValue = !product.isPurchasedValue
            product.isPurchased = NSNumber(value: nextValue)
            product.purchasedAt = nextValue ? now : nil
            product.purchasedByName = nextValue
                ? participantDisplayName?.trimmedNilIfEmpty
                : nil
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    func deleteProduct(id: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try Self.fetchProduct(id: id, in: context) else {
                throw RepositoryError.productNotFound
            }
            try self.requireDeletePermission(for: product)
            let now = Date()
            product.deletedAt = now
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    @discardableResult
    func completePurchased(listID: UUID) async throws -> UUID? {
        try await persistence.performBackgroundTask { context in
            guard let list = try Self.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            try self.requireUpdatePermission(for: list)
            guard let space = list.familySpace else {
                throw RepositoryError.familySpaceNotFound
            }

            let purchased = list.sortedProducts.filter(\.isPurchasedValue)
            guard !purchased.isEmpty else { return nil }

            let now = Date()
            let historyID = UUID()
            let history = PurchaseHistoryEntity(context: context)
            try self.persistence.assign(history, toSameStoreAs: list, in: context)
            history.id = historyID
            history.total = NSNumber(
                value: purchased.reduce(0) { $0 + $1.estimatedPriceValue }
            )
            history.date = now
            history.createdAt = now
            history.updatedAt = now
            history.familySpace = space
            history.store = list.store

            let names = Set(
                purchased.compactMap { $0.purchasedByName?.trimmedNilIfEmpty }
            ).sorted()
            history.memberNames = names.isEmpty ? "Группа" : names.joined(separator: ", ")

            for product in purchased {
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
                item.storeName = product.store?.name
                item.createdAt = product.createdAt
                item.updatedAt = now
                item.familySpace = space
                item.history = history
                product.deletedAt = now
                product.updatedAt = now
            }

            list.updatedAt = now
            space.updatedAt = now
            return historyID
        }
    }

    func deleteHistory(id: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            let request = PurchaseHistoryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
            request.fetchLimit = 1
            guard let history = try context.fetch(request).first else { return }
            try self.requireDeletePermission(for: history)
            let now = Date()
            history.deletedAt = now
            history.updatedAt = now
            for item in history.items?.allObjects as? [HistoryItemEntity] ?? [] {
                item.deletedAt = now
                item.updatedAt = now
            }
            history.familySpace?.updatedAt = now
        }
    }

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

    private func requireUpdatePermission(for object: NSManagedObject) throws {
        guard permissionAuthorizer.canUpdate(object.objectID) else {
            throw RepositoryError.permissionDenied
        }
    }

    private func requireDeletePermission(for object: NSManagedObject) throws {
        guard permissionAuthorizer.canDelete(object.objectID) else {
            throw RepositoryError.permissionDenied
        }
    }

    private static func apply(draft: ProductDraft, to product: ProductEntity) {
        product.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        product.quantity = NSNumber(value: max(draft.quantity, 0.001))
        product.unit = draft.unit.rawValue
        product.category = draft.category.rawValue
        product.estimatedPrice = NSNumber(value: max(draft.estimatedPrice, 0))
        product.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        product.imageURL = draft.imageURL?.trimmedNilIfEmpty
        product.sourceURL = draft.sourceURL?.trimmedNilIfEmpty
        product.originalPrice = draft.originalPrice.map { NSNumber(value: max($0, 0)) }
        product.loyaltyPrice = draft.loyaltyPrice.map { NSNumber(value: max($0, 0)) }
        product.catalogFetchedAt = draft.catalogFetchedAt
        product.promotionEndsAt = draft.promotionEndsAt
    }

    private static func fetchFamilySpace(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace? {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func requireFamilySpace(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace {
        guard let space = try fetchFamilySpace(id: id, in: context) else {
            throw RepositoryError.familySpaceNotFound
        }
        return space
    }

    private static func fetchList(
        id: UUID,
        familySpaceID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> ShoppingListEntity? {
        let request = ShoppingListEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ]
        if let familySpaceID {
            predicates.append(
                NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID)
            )
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func fetchProduct(
        id: UUID,
        familySpaceID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> ProductEntity? {
        let request = ProductEntity.fetchRequest()
        var predicates = [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ]
        if let familySpaceID {
            predicates.append(
                NSPredicate(format: "familySpace.id == %@", familySpaceID as NSUUID)
            )
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func deduplicate<T: NSManagedObject>(
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
        return candidateDate > existingDate ? candidate : existing
    }
}

protocol SoftDeletable: AnyObject {
    var deletedAt: Date? { get set }
}

protocol Timestamped: AnyObject {
    var updatedAt: Date? { get set }
}

extension FamilySpace: SoftDeletable, Timestamped {}
extension StoreEntity: SoftDeletable, Timestamped {}
extension ShoppingListEntity: SoftDeletable, Timestamped {}
extension ProductEntity: SoftDeletable, Timestamped {}
extension PurchaseHistoryEntity: SoftDeletable, Timestamped {}

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
