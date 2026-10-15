import CloudKit
import CoreData
import Foundation
import OSLog

@MainActor
final class FamilyShareOrchestrator {
    private let persistence: PersistenceController
    /// Background invite preparation reads the existing share straight from the container,
    /// whichever `FamilyCloudSharing` the session runs on.
    private let shareStore: any CloudKitShareStoring
    private let cloudSharing: any FamilyCloudSharing

    init(
        persistence: PersistenceController,
        shareStore: any CloudKitShareStoring,
        cloudSharing: any FamilyCloudSharing
    ) {
        self.persistence = persistence
        self.shareStore = shareStore
        self.cloudSharing = cloudSharing
    }

    func ensureOwnerReadWriteACL(for family: FamilySpace, isOwner: Bool) async {
        guard isOwner else { return }
        guard let scope = persistence.scope(for: family), scope == .private || scope == .shared else {
            return
        }
        do {
            let changed = try await cloudSharing.ensureReadWriteACL(objectID: family.objectID)
            if changed {
                CartSyncLog.shareACL.info(
                    "owner ACL heal persisted hasURL=true scope=\(scope.rawValue, privacy: .public)"
                )
            }
        } catch {
            CartSyncLog.shareACL.error(
                "owner ACL heal failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func existingInviteLink(for family: FamilySpace) async throws -> FamilyInviteLink {
        try await FamilyInviteLinkBuilder.existingInviteLink(
            persistence: persistence,
            shareStore: shareStore,
            objectID: family.objectID,
            displayName: family.displayName
        )
    }

    func createInviteLink(for family: FamilySpace) async throws -> FamilyInviteLink {
        let objectID = family.objectID
        let displayName = family.displayName
        let viewContext = persistence.container.viewContext
        if viewContext.hasChanges {
            try viewContext.save()
        }
        let cloudSharing = cloudSharing
        let task = Task.detached(priority: .userInitiated) {
            try await cloudSharing.createFamilyInviteLink(
                objectID: objectID,
                displayName: displayName
            )
        }
        let link = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        CartSyncLog.shareACL.info(
            "invite link ready hasURL=true host=\(link.url.host ?? "-", privacy: .public)"
        )
        return link
    }

    func revokeInviteLink(for family: FamilySpace) async throws {
        let familyID = family.id
        let objectID = family.objectID
        CartSyncLog.action.info(
            "revokeInvite start family=\(familyID?.uuidString ?? "-", privacy: .public)"
        )
        let cloudSharing = cloudSharing
        let task = Task.detached(priority: .userInitiated) {
            try await cloudSharing.revokeInviteLink(objectID: objectID)
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        CartSyncLog.action.info("revokeInvite done")
    }
}
