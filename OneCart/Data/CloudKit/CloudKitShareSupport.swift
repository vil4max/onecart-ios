import CloudKit

/// The CloudKit environment of this build, stamped as the local store marker. Debug and Release
/// entitlements both pin `com.apple.developer.icloud-container-environment` to Production, so the
/// process only ever sees Production shares and needs no per-share environment check.
enum CloudKitShareEnvironment: String {
    case production
    /// Never stamped by a shipped build; kept so a Development-mirrored store would still be wiped.
    case development

    static let process: CloudKitShareEnvironment = .production
}

enum OneCartShareBranding {
    static let title = "OneCart Family"

    /// Stamps the title, and the thumbnail only on a share that has none, so an existing
    /// thumbnail is never redrawn. Without a renderer the share keeps no thumbnail.
    @discardableResult
    static func apply(to share: CKShare, thumbnail: (any ShareThumbnailRendering)?) -> Bool {
        var changed = false
        if (share[CKShare.SystemFieldKey.title] as? String) != title {
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue
            changed = true
        }
        if share[CKShare.SystemFieldKey.thumbnailImageData] == nil, let data = thumbnail?.thumbnailPNGData() {
            share[CKShare.SystemFieldKey.thumbnailImageData] = data as CKRecordValue
            changed = true
        }
        return changed
    }
}

enum OneCartShareLinkJoin {
    @discardableResult
    static func applyReadWriteACL(to share: CKShare, reopenInviteDoor: Bool = false) -> Bool {
        var changed = false
        let mayTouchPublicPermission = reopenInviteDoor || share.publicPermission != .none
        if mayTouchPublicPermission, share.publicPermission != .readWrite {
            share.publicPermission = .readWrite
            changed = true
        }
        if ShareParticipantRules.grantReadWrite(to: share.participants) {
            changed = true
        }
        return changed
    }
}

/// What share mutations read and change on one participant. `CKShare.Participant` has no public
/// initializer, so this seam lets tests drive the decisions below with plain objects; the
/// CloudKit type is the only production conformer. Class-bound because a permission change must
/// land on the participant the share holds.
protocol ShareParticipantHandle: AnyObject {
    var userRecordName: String? { get }
    var lookupEmailAddress: String? { get }
    var lookupPhoneNumber: String? { get }
    var isOwner: Bool { get }
    var permission: CKShare.ParticipantPermission { get set }
}

extension CKShare.Participant: ShareParticipantHandle {
    var userRecordName: String? {
        userIdentity.userRecordID?.recordName
    }

    var lookupEmailAddress: String? {
        userIdentity.lookupInfo?.emailAddress
    }

    var lookupPhoneNumber: String? {
        userIdentity.lookupInfo?.phoneNumber
    }

    var isOwner: Bool {
        role == .owner
    }
}

/// Participant decisions of the share mutations, free of CloudKit I/O.
enum ShareParticipantRules {
    /// The identity CloudKit exposes for a participant (REQ-SHARE-040): record name, then lookup
    /// email, then lookup phone number — the same order the members list and removal both use, so
    /// a listed member always resolves to the participant that produced its row. A record name or
    /// email that CloudKit reports as an empty string is not skipped in favor of the next kind:
    /// only a missing (`nil`) value falls through, matching the members list's existing guard that
    /// drops a row on an empty key rather than resolving it against a lower-priority identity.
    static func memberKey(for participant: some ShareParticipantHandle) -> String? {
        participant.userRecordName ?? participant.lookupEmailAddress ?? participant.lookupPhoneNumber
    }

    /// The participant a members-list row stands for (REQ-SHARE-040): the row id is the stable
    /// UUID of `memberKey(for:)`.
    static func participant<Participant: ShareParticipantHandle>(
        forMemberID memberID: UUID,
        in participants: [Participant]
    ) -> Participant? {
        participants.first { participant in
            memberKey(for: participant).map(FamilyInviteLinkBuilder.stableUUID(for:)) == memberID
        }
    }

    /// Every non-owner participant may edit the cart (REQ-SHARE-020); the owner is never touched.
    /// Returns whether any permission changed.
    static func grantReadWrite(to participants: [some ShareParticipantHandle]) -> Bool {
        var changed = false
        for participant in participants where !participant.isOwner {
            guard participant.permission != .readWrite else { continue }
            participant.permission = .readWrite
            changed = true
        }
        return changed
    }
}
