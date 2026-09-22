import CoreData
import Foundation

extension FamilySpaceRepository {
    /// Writes this member's name into the cart so other members can show it (REQ-AUTH-040).
    /// Idempotent: nothing is saved when the newest row already carries the name. Older rows
    /// of the same member become tombstones. A member without a name gets no new row, and an
    /// existing row loses its name so the others fall back to the numbered label.
    /// - Returns: whether anything was written.
    @discardableResult
    func upsertMemberProfile(
        familySpaceID: UUID,
        userRecordName: String,
        displayName: String?,
        now: Date = Date()
    ) async throws -> Bool {
        let recordName = userRecordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordName.isEmpty else { return false }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmptyProfileName

        return try await persistence.performBackgroundTask(author: "OneCartMemberProfile") { context in
            let space = try Self.requireFamilySpace(id: familySpaceID, in: context)
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

private extension String {
    var nilIfEmptyProfileName: String? {
        isEmpty ? nil : self
    }
}
