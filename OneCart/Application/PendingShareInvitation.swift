import CloudKit
import Foundation

/// A share invitation the system handed the app, reduced to what the accept path decides on.
/// `CKShare.Metadata` has no public initializer, so tests build invitations from the values
/// alone and leave `metadata` nil; only the container's accept call needs the metadata itself.
struct PendingShareInvitation: @unchecked Sendable {
    let participantStatus: CKShare.ParticipantAcceptanceStatus
    let shareRecordName: String
    let rootRecordID: CKRecord.ID?
    let metadata: CKShare.Metadata?

    init(
        participantStatus: CKShare.ParticipantAcceptanceStatus,
        shareRecordName: String,
        rootRecordID: CKRecord.ID?,
        metadata: CKShare.Metadata? = nil
    ) {
        self.participantStatus = participantStatus
        self.shareRecordName = shareRecordName
        self.rootRecordID = rootRecordID
        self.metadata = metadata
    }

    init(metadata: CKShare.Metadata) {
        self.init(
            participantStatus: metadata.participantStatus,
            shareRecordName: metadata.share.recordID.recordName,
            rootRecordID: metadata.hierarchicalRootRecordID,
            metadata: metadata
        )
    }
}

/// Accepts invitations into the shared store. `PersistenceController.acceptShareInvitations`
/// is the only container call of the share code outside `CloudKitShareStoring`.
protocol ShareInvitationAccepting: Sendable {
    func acceptShareInvitations(_ invitations: [PendingShareInvitation]) async throws
}

extension PersistenceController: ShareInvitationAccepting {
    func acceptShareInvitations(_ invitations: [PendingShareInvitation]) async throws {
        try await acceptShareInvitations(from: invitations.compactMap(\.metadata))
    }
}
