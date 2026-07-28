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
            "invite link ready hasURL=true host=\(link.url.host ?? "-", privacy: .public)"
        )
        return link
    }

    func deleteCurrentCartAndStartFresh(
        family: FamilySpace,
        accountID: UUID,
        defaultFamilyName: String
    ) async throws -> UUID {
        let familyID = family.id
        let objectID = family.objectID
        CartSyncLog.action.info(
            "deleteCart start family=\(familyID?.uuidString ?? "-", privacy: .public) name=\(family.displayName, privacy: .public)"
        )
        CartSyncLog.shareACL.info("delete cart start rotating share URL")

        let backend = backend
        do {
            try await Task.detached(priority: .userInitiated) {
                try await backend.stopSharing(objectID: objectID)
            }.value
            CartSyncLog.action.info("deleteCart stopSharing done")
        } catch {
            CartSyncLog.shareACL.error(
                "stopSharing soft-fail error=\(error.localizedDescription, privacy: .public)"
            )
            CartSyncLog.action.error(
                "deleteCart stopSharing soft-fail error=\(error.localizedDescription, privacy: .public)"
            )
        }

        if let familyID {
            CartSyncLog.action.info("deleteCart archive family=\(familyID.uuidString, privacy: .public)")
            try await repository.archiveFamilySpace(id: familyID)
        }
        let newID = try await repository.createFamilySpace(
            name: defaultFamilyName,
            cachedForUserID: accountID,
            isHouseholdDefault: true
        )
        CartSyncLog.shareACL.info("delete cart done newFamily created")
        CartSyncLog.action.info(
            "deleteCart done newFamily=\(newID.uuidString, privacy: .public) name=\(defaultFamilyName, privacy: .public)"
        )
        return newID
    }
}
