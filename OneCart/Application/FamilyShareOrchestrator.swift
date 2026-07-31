import CloudKit
import CoreData
import Foundation
import OSLog

@MainActor
final class FamilyShareOrchestrator {
    private let persistence: PersistenceController
    private let backend: CloudKitBackendService
    private let repository: FamilySpaceRepository

    init(
        persistence: PersistenceController,
        backend: CloudKitBackendService,
        repository: FamilySpaceRepository
    ) {
        self.persistence = persistence
        self.backend = backend
        self.repository = repository
    }

    func ensureOwnerReadWriteACL(for family: FamilySpace, isOwner: Bool) async {
        guard isOwner, !persistence.inMemory else { return }
        guard persistence.scope(for: family) == .private else { return }
        do {
            let changed = try await backend.ensureReadWriteACL(for: family)
            if changed {
                CartSyncLog.shareACL.info("owner ACL heal persisted hasURL=true")
            }
        } catch {
            CartSyncLog.shareACL.error(
                "owner ACL heal failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func createInviteLink(for family: FamilySpace) async throws -> FamilyInviteLink {
        let objectID = family.objectID
        let displayName = family.displayName
        let viewContext = persistence.container.viewContext
        if viewContext.hasChanges {
            try viewContext.save()
        }
        let backend = backend
        let link = try await Task.detached(priority: .userInitiated) {
            try await backend.createFamilyInviteLink(
                objectID: objectID,
                displayName: displayName
            )
        }.value
        CartSyncLog.shareACL.info(
            "invite door repaired hasURL=true host=\(link.url.host ?? "-", privacy: .public)"
        )
        return link
    }

    func revokeInviteLink(for family: FamilySpace) async throws {
        let familyID = family.id
        let objectID = family.objectID
        CartSyncLog.action.info(
            "revokeInvite start family=\(familyID?.uuidString ?? "-", privacy: .public)"
        )
        let backend = backend
        try await Task.detached(priority: .userInitiated) {
            try await backend.revokeInviteLink(objectID: objectID)
        }.value
        CartSyncLog.action.info("revokeInvite done")
    }
}
