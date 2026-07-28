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
            String(localized: "sync.error.family_not_found")
        case .listNotFound:
            String(localized: "sync.error.list_not_found")
        case .productNotFound:
            String(localized: "sync.error.product_not_found")
        case .storeNotFound:
            String(localized: "sync.error.store_not_found")
        case .permissionDenied:
            String(localized: "sync.error.permission_denied")
        case .crossShareRelationship:
            String(localized: "sync.error.cross_share")
        case .invalidName:
            String(localized: "sync.error.invalid_name")
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
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing

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
            list.title = String(localized: "common.default_list")
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = createdAt
            list.updatedAt = createdAt
            list.familySpace = space

            return id
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

    func requireUpdatePermission(for object: NSManagedObject) throws {
        guard permissionAuthorizer.canUpdate(object.objectID) else {
            throw RepositoryError.permissionDenied
        }
    }

    func requireDeletePermission(for object: NSManagedObject) throws {
        guard permissionAuthorizer.canDelete(object.objectID) else {
            throw RepositoryError.permissionDenied
        }
    }


    static func fetchFamilySpace(
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

    static func requireFamilySpace(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace {
        guard let space = try fetchFamilySpace(id: id, in: context) else {
            throw RepositoryError.familySpaceNotFound
        }
        return space
    }

    static func fetchList(
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

    static func fetchProduct(
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
