import CloudKit
import CoreData
import Foundation
import Synchronization

final class CloudKitBackendService: Sendable {
    /// How long a leave waits for the zone purge before it reports `leaveTimedOut`.
    static let leavePurgeTimeout: Duration = .seconds(22)

    let persistence: PersistenceController
    let shareStore: any CloudKitShareStoring
    private let lazyCloudContainer: LazyCloudContainer
    private let clock: AppClock
    let userRecordNameCache = Mutex(UserRecordNameCache())
    /// Written once in `init` and read only in `deinit`, so no two threads touch it at once.
    nonisolated(unsafe) private var accountChangeObserver: (any NSObjectProtocol)?

    var cloudContainer: CKContainer {
        lazyCloudContainer.container
    }

    /// Without `shareStore` the backend talks to the live container of `persistence` and stamps
    /// no share thumbnail; the composition root always passes its store.
    init(
        persistence: PersistenceController,
        cloudContainer: LazyCloudContainer = LazyCloudContainer(),
        shareStore: (any CloudKitShareStoring)? = nil,
        clock: AppClock = .live
    ) {
        self.persistence = persistence
        lazyCloudContainer = cloudContainer
        self.shareStore =
            shareStore
            ?? LiveCloudKitShareStore(persistence: persistence, cloudContainer: cloudContainer, shareThumbnail: nil)
        self.clock = clock
        // The backend outlives an iCloud account switch; the old record name would publish this
        // member's profile under the previous user.
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.resetCachedUserRecordName()
        }
    }

    deinit {
        if let accountChangeObserver {
            NotificationCenter.default.removeObserver(accountChangeObserver)
        }
    }

    func resetCachedUserRecordName() {
        userRecordNameCache.withLock { $0.reset() }
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await shareStore.accountStatus()
    }

    func restoredAccount(
        appleUserID: String,
        displayName: String?
    ) async throws -> OneCartAccount {
        if !persistence.cloudKitEnabled {
            return OneCartAccount(
                id: OneCartStableID.uuid(for: "apple:\(appleUserID)"),
                displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
            )
        }

        #if targetEnvironment(simulator)
            let status = await (try? accountStatus()) ?? .noAccount
            if status != .available {
                return OneCartAccount(
                    id: OneCartStableID.uuid(for: "apple:\(appleUserID)"),
                    displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
                )
            }
        #else
            let status = try await accountStatus()
            guard status == .available else {
                throw OneCartCloudKitError.accountUnavailable(status)
            }
        #endif
        return OneCartAccount(
            id: OneCartStableID.uuid(for: "apple:\(appleUserID)"),
            displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
        )
    }

    func access(for family: FamilySpace) -> FamilyAccess {
        persistence.scope(for: family) == .shared ? .member : .owner
    }

    /// Prefer calling this after flushing the view context and reading `objectID` / name
    /// on the MainActor so CloudKit work does not hold the UI actor.
    func createFamilyInviteLink(
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        let persistence = persistence
        let shareStore = shareStore
        let clock = clock
        // CloudKitDeadline releases the caller even when an SDK callback ignores cancellation;
        // the ceiling and why it is below the builder's worst case: FamilyInviteShareBudget.
        return try await CloudKitDeadline.run(
            timeoutNanoseconds: FamilyInviteShareBudget.inviteCeilingNanoseconds,
            timeoutError: OneCartCloudKitError.shareTimedOut
        ) {
            try await FamilyInviteLinkBuilder.makeInviteLink(
                persistence: persistence,
                shareStore: shareStore,
                objectID: objectID,
                displayName: displayName,
                clock: clock
            )
        }
    }
}

// MARK: - Members

extension CloudKitBackendService {
    func familyMembers(
        for family: FamilySpace,
        account: OneCartAccount,
        currentUserRecordName: String? = nil
    ) throws -> [FamilyMember] {
        guard let share = try share(for: family) else {
            let currentUser = FamilyMember(
                id: account.id,
                displayName: account.displayName,
                access: access(for: family),
                joinedAt: family.createdDate,
                isCurrentUser: true,
                avatarURL: nil,
                bannerURL: nil
            )
            return [currentUser]
        }

        let currentRecordName = share.currentUserParticipant?
            .userIdentity.userRecordID?.recordName
        let participants = share.participants.compactMap { participant -> ShareParticipantSummary? in
            guard let recordName = ShareParticipantRules.memberKey(for: participant), !recordName.isEmpty else {
                return nil
            }
            let name = participant.userIdentity.nameComponents.map {
                PersonNameComponentsFormatter.localizedString(
                    from: $0,
                    style: .default,
                    options: []
                )
            }?.nilIfBlank
            return ShareParticipantSummary(
                recordName: recordName,
                identityName: name,
                isOwner: participant.role == .owner,
                isCurrentUser: recordName == currentRecordName
            )
        }
        return FamilyMemberNaming.members(
            participants: participants,
            profileNames: MemberProfileNames.latest(in: family),
            currentUserRecordName: currentUserRecordName,
            account: account,
            joinedAt: family.createdDate
        )
    }

    /// Async share mutations take the object ID: a view-context `FamilySpace` must not
    /// leave the main actor.
    func removeMember(_ member: FamilyMember, fromFamily objectID: NSManagedObjectID) async throws {
        guard let share = try share(forObjectID: objectID) else {
            throw OneCartCloudKitError.familyNotShared
        }
        guard let participant = ShareParticipantRules.participant(forMemberID: member.id, in: share.participants)
        else {
            throw OneCartCloudKitError.participantNotFound
        }
        let doorBefore = share.publicPermission
        CartSyncLog.shareACL.info(
            "removeMember kick (not ban) doorBefore=\(String(describing: doorBefore), privacy: .public)"
        )
        share.removeParticipant(participant)
        let saved = try await shareStore.persistShare(share, in: .private)
        let doorAfter = saved.publicPermission
        CartSyncLog.shareACL.info(
            "removeMember done doorAfter=\(String(describing: doorAfter), privacy: .public)"
        )
        if doorBefore == .readWrite, doorAfter == .none {
            CartSyncLog.shareACL.error(
                "removeMember unexpected invite door closed after kick; not auto-reopening"
            )
        }
    }
}

// MARK: - Leave

extension CloudKitBackendService {
    @discardableResult
    func leaveFamily(
        objectID: NSManagedObjectID,
        onLatePurgeCompletion: @escaping @Sendable () -> Void
    ) async throws -> Bool {
        let zoneID: CKRecordZone.ID
        if let share = try share(forObjectID: objectID) {
            CartSyncLog.shareACL.info(
                "leaveFamily begin record=\(share.recordID.recordName, privacy: .public)"
            )
            zoneID = share.recordID.zoneID
        } else if let recordID = shareStore.recordID(for: objectID) {
            CartSyncLog.shareACL.info(
                "leaveFamily begin via record zone=\(recordID.zoneID.zoneName, privacy: .public)"
            )
            zoneID = recordID.zoneID
        } else {
            CartSyncLog.shareACL.error("leaveFamily no share or record zone")
            throw OneCartCloudKitError.familyNotShared
        }

        do {
            try await purgeSharedZone(zoneID, onLateCompletion: onLatePurgeCompletion)
            return true
        } catch {
            if CloudKitUserFacingError.isBenignShareLeaveFailure(error) {
                CartSyncLog.shareACL.info(
                    "leaveFamily treat zone-gone error=\(error.localizedDescription, privacy: .public)"
                )
                return true
            }
            throw error
        }
    }

    /// A purge that outlives the timeout still clears the shared zone, so its completion is
    /// handed to the caller's leave recovery (REQ-SHARE-050) instead of being dropped.
    private func purgeSharedZone(
        _ zoneID: CKRecordZone.ID,
        onLateCompletion: @escaping @Sendable () -> Void
    ) async throws {
        let shareStore = shareStore
        let clock = clock
        try await CloudKitDeadline.run(
            timeout: { try await clock.sleep(Self.leavePurgeTimeout) },
            timeoutError: OneCartCloudKitError.leaveTimedOut,
            onLateCompletion: { _ in
                CartSyncLog.shareACL.info("leaveFamily late purge finished after timeout")
                onLateCompletion()
            },
            operation: {
                try await shareStore.purgeObjectsAndRecordsInZone(with: zoneID, in: .shared)
            }
        )
    }
}

// MARK: - Invite door

extension CloudKitBackendService {
    @discardableResult
    func ensureReadWriteACL(objectID: NSManagedObjectID) async throws -> Bool {
        guard let share = try share(forObjectID: objectID) else { return false }
        // The heal never reopens a revoked invite door; only Share does (REQ-SHARE-060).
        let saved = try await shareStore.applyReadWriteACL(
            to: share,
            reopenInviteDoor: false,
            in: persistence.scope(for: objectID) ?? .private
        )
        return saved != nil
    }

    func revokeInviteLink(objectID: NSManagedObjectID) async throws {
        guard let share = try share(forObjectID: objectID) else {
            CartSyncLog.shareACL.info("revokeInvite skip no-share")
            throw OneCartCloudKitError.familyNotShared
        }
        CartSyncLog.shareACL.info(
            "revokeInvite begin record=\(share.recordID.recordName, privacy: .public) hasURL=\(share.url != nil)"
        )
        guard share.publicPermission != .none else {
            CartSyncLog.shareACL.info("revokeInvite already closed")
            return
        }
        share.publicPermission = .none
        do {
            _ = try await shareStore.persistShare(share, in: .private, timeoutNanoseconds: 8_000_000_000)
            CartSyncLog.shareACL.info("revokeInvite persist done")
        } catch {
            CartSyncLog.shareACL.error(
                "revokeInvite persist fail error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func share(for family: FamilySpace) throws -> CKShare? {
        try share(forObjectID: family.objectID)
    }

    private func share(forObjectID objectID: NSManagedObjectID) throws -> CKShare? {
        try shareStore.fetchShare(for: objectID)
    }
}
