import CoreData
import Foundation

protocol PermissionAuthorizing: AnyObject, Sendable {
    func canUpdate(_ objectID: NSManagedObjectID) -> Bool
    func canDelete(_ objectID: NSManagedObjectID) -> Bool
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

/// What an add or a rename writes to a cart line (REQ-CART-020, REQ-CART-060): the name and the
/// category it is grouped under. The legacy quantity, unit, price, note, URL and catalog
/// attributes stay in the model for CloudKit and older clients, but the app no longer writes
/// them, so values an older build stored are left as they are.
struct ProductDraft: Equatable {
    var name: String
    var category: ProductCategory
}

final class FamilySpaceRepository: Sendable {
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing

    init(
        persistence: PersistenceController,
        permissionAuthorizer: PermissionAuthorizing
    ) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
    }

    /// Reads the view context, so the objects it returns belong to the main actor.
    @MainActor
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

    /// Reads the view context, so the object it returns belongs to the main actor.
    @MainActor
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
            space.isHouseholdDefault = NSNumber(value: isHouseholdDefault)

            let list = ShoppingListEntity(context: context)
            try self.persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = UUID()
            list.title = String(localized: "common.default_list")
            // v1.2.1 shows only lists whose status is "active"; every new list keeps writing it.
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

    func discardLocalSharedFamilySpace(id: UUID) async throws {
        try await persistence.performBackgroundTask(author: "OneCartLeaveShared") { context in
            let space = try Self.requireFamilySpace(id: id, in: context)
            guard self.persistence.scope(for: space) == .shared else { return }
            context.delete(space)
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
