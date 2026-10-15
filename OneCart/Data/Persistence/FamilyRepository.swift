import CoreData
import Foundation

/// Family spaces and their default list: reads for the session, create, account claim, rename,
/// and the local discard of a shared cart this device left.
protocol FamilyRepository: Sendable {
    /// Reads the view context, so the objects it returns belong to the main actor.
    @MainActor func fetchFamilySpaces(for userID: UUID?) throws -> [FamilySpace]
    /// Reads the view context, so the object it returns belongs to the main actor.
    @MainActor func fetchFamilySpace(id: UUID) throws -> FamilySpace?
    func createFamilySpace(
        id: UUID,
        name: String,
        createdAt: Date?,
        cachedForUserID: UUID?,
        isHouseholdDefault: Bool
    ) async throws -> UUID
    func claimUnassignedFamilySpaces(for userID: UUID) async throws
    func renameFamilySpace(id: UUID, name: String) async throws
    func discardLocalSharedFamilySpace(id: UUID) async throws
}

final class CoreDataFamilyRepository: FamilyRepository, PermissionGuardedRepository, Sendable {
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing
    let clock: AppClock

    init(persistence: PersistenceController, permissionAuthorizer: PermissionAuthorizing, clock: AppClock) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
        self.clock = clock
    }

    @MainActor
    func fetchFamilySpaces(for userID: UUID?) throws -> [FamilySpace] {
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

    @MainActor
    func fetchFamilySpace(id: UUID) throws -> FamilySpace? {
        try RepositoryFetch.familySpace(id: id, in: persistence.container.viewContext)
    }

    func createFamilySpace(
        id: UUID,
        name: String,
        createdAt: Date?,
        cachedForUserID: UUID?,
        isHouseholdDefault: Bool
    ) async throws -> UUID {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }
        let createdAt = createdAt ?? clock.now()

        return try await persistence.performBackgroundTask { context in
            if let existing = try RepositoryFetch.familySpace(id: id, in: context) {
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
            let space = try RepositoryFetch.requireFamilySpace(id: id, in: context)
            try self.requireUpdatePermission(for: space)
            space.name = normalizedName
            space.updatedAt = self.clock.now()
        }
    }

    func discardLocalSharedFamilySpace(id: UUID) async throws {
        try await persistence.performBackgroundTask(author: "OneCartLeaveShared") { context in
            let space = try RepositoryFetch.requireFamilySpace(id: id, in: context)
            guard self.persistence.scope(for: space) == .shared else { return }
            context.delete(space)
        }
    }
}
