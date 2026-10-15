import CoreData
import Foundation

/// Each member's chosen name in the cart's zone, keyed by their CloudKit user record name.
protocol MemberProfileStore: Sendable {
    /// Writes this member's name into the cart so other members can show it (REQ-AUTH-040).
    /// - Returns: whether anything was written.
    @discardableResult
    func upsertMemberProfile(
        familySpaceID: UUID,
        userRecordName: String,
        displayName: String?,
        now: Date?
    ) async throws -> Bool
}

final class CoreDataMemberProfileStore: MemberProfileStore, PermissionGuardedRepository, Sendable {
    let persistence: PersistenceController
    let permissionAuthorizer: PermissionAuthorizing
    let clock: AppClock

    init(persistence: PersistenceController, permissionAuthorizer: PermissionAuthorizing, clock: AppClock) {
        self.persistence = persistence
        self.permissionAuthorizer = permissionAuthorizer
        self.clock = clock
    }

    /// Idempotent: nothing is saved when the newest row already carries the name. Older rows
    /// of the same member become tombstones. A member without a name gets no new row, and an
    /// existing row loses its name so the others fall back to the numbered label.
    @discardableResult
    func upsertMemberProfile(
        familySpaceID: UUID,
        userRecordName: String,
        displayName: String?,
        now: Date?
    ) async throws -> Bool {
        let recordName = userRecordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordName.isEmpty else { return false }
        let name = displayName?.nilIfBlank
        let now = now ?? clock.now()

        return try await persistence.performBackgroundTask(author: "OneCartMemberProfile") { context in
            let space = try RepositoryFetch.requireFamilySpace(id: familySpaceID, in: context)
            let request = MemberProfileEntity.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "familySpace == %@", space),
                NSPredicate(format: "userRecordName == %@", recordName),
                NSPredicate(format: "deletedAt == nil"),
            ])
            let rows = try context.fetch(request)
            let ordered = rows.sorted { MemberProfileNames.isPreferred($0, over: $1) }

            guard let winner = ordered.first else {
                guard let name else { return false }
                try self.requireUpdatePermission(for: space)
                let profile = MemberProfileEntity(context: context)
                try self.persistence.assign(profile, toSameStoreAs: space, in: context)
                profile.id = UUID()
                profile.userRecordName = recordName
                profile.displayName = name
                profile.createdAt = now
                profile.updatedAt = now
                profile.familySpace = space
                return true
            }

            var changed = false
            for loser in ordered.dropFirst() where self.permissionAuthorizer.canUpdate(loser.objectID) {
                loser.deletedAt = now
                loser.updatedAt = now
                changed = true
            }
            if winner.displayName != name {
                try self.requireUpdatePermission(for: winner)
                winner.displayName = name
                winner.updatedAt = now
                changed = true
            }
            return changed
        }
    }
}
