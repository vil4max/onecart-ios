import CloudKit
import CoreData
import Foundation
import Synchronization

final class CloudKitBackendService: Sendable {
    let persistence: PersistenceController
    private let injectedCloudContainer: CKContainer?
    private let cachedCloudContainer = Mutex<CKContainer?>(nil)
    let userRecordNameCache = Mutex(UserRecordNameCache())
    /// Written once in `init` and read only in `deinit`, so no two threads touch it at once.
    nonisolated(unsafe) private var accountChangeObserver: (any NSObjectProtocol)?

    /// Lazily created — constructing `CKContainer` in unit tests / Xcode Cloud without iCloud can SEGV.
    var cloudContainer: CKContainer {
        if let injectedCloudContainer {
            return injectedCloudContainer
        }
        return cachedCloudContainer.withLock { cached in
            if let cached {
                return cached
            }
            let created = CKContainer(
                identifier: PersistenceController.cloudKitContainerIdentifier
            )
            cached = created
            return created
        }
    }

    init(
        persistence: PersistenceController,
        cloudContainer: CKContainer? = nil
    ) {
        self.persistence = persistence
        injectedCloudContainer = cloudContainer
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
        // CloudKitDeadline releases the caller even when an SDK callback ignores cancellation;
        // the ceiling and why it is below the builder's worst case: FamilyInviteShareBudget.
        return try await CloudKitDeadline.run(
            timeoutNanoseconds: FamilyInviteShareBudget.inviteCeilingNanoseconds,
            timeoutError: OneCartCloudKitError.shareTimedOut
        ) {
            try await FamilyInviteLinkBuilder.makeInviteLink(
                persistence: persistence,
                objectID: objectID,
                displayName: displayName
            )
        }
    }

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
        let store = try persistence.store(for: .private)
        let saved = try await persist(share, in: store)
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

    @discardableResult
    func leaveFamily(objectID: NSManagedObjectID) async throws -> Bool {
        let zoneID: CKRecordZone.ID
        if let share = try share(forObjectID: objectID) {
            CartSyncLog.shareACL.info(
                "leaveFamily begin record=\(share.recordID.recordName, privacy: .public)"
            )
            zoneID = share.recordID.zoneID
        } else if let recordID = persistence.container.recordID(for: objectID) {
            CartSyncLog.shareACL.info(
                "leaveFamily begin via record zone=\(recordID.zoneID.zoneName, privacy: .public)"
            )
            zoneID = recordID.zoneID
        } else {
            CartSyncLog.shareACL.error("leaveFamily no share or record zone")
            throw OneCartCloudKitError.familyNotShared
        }

        let sharedStore = try persistence.store(for: .shared)
        do {
            try await purgeSharedZone(zoneID, in: sharedStore)
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

    private func purgeSharedZone(
        _ zoneID: CKRecordZone.ID,
        in store: NSPersistentStore,
        timeoutNanoseconds: UInt64 = 22_000_000_000
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = LeavePurgeSettleGate()

            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                guard gate.trySettle() else { return }
                continuation.resume(throwing: OneCartCloudKitError.leaveTimedOut)
            }

            persistence.container.purgeObjectsAndRecordsInZone(
                with: zoneID,
                in: store
            ) { _, error in
                let shouldResume = gate.trySettle()
                timeoutTask.cancel()

                guard shouldResume else {
                    CartSyncLog.shareACL.info("leaveFamily late purge finished after timeout")
                    NotificationCenter.default.post(
                        name: .oneCartDidFinishLateLeavePurge,
                        object: nil
                    )
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// MARK: - Invite door

extension CloudKitBackendService {
    @discardableResult
    func ensureReadWriteACL(objectID: NSManagedObjectID) async throws -> Bool {
        guard let share = try share(forObjectID: objectID) else { return false }
        var needsPersist = false
        if OneCartShareLinkJoin.applyReadWriteACL(to: share) {
            needsPersist = true
        }
        if OneCartShareBranding.apply(to: share) {
            needsPersist = true
        }
        guard needsPersist else { return false }
        let storeScope = persistence.scope(for: objectID) ?? .private
        let store = try persistence.store(for: storeScope)
        _ = try await persist(share, in: store)
        return true
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
        let store = try persistence.store(for: .private)
        do {
            _ = try await persist(share, in: store, timeoutNanoseconds: 8_000_000_000)
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
        try persistence.container.fetchShares(matching: [objectID])[objectID]
    }

}

private final class LeavePurgeSettleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var settled = false

    func trySettle() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else { return false }
        settled = true
        return true
    }
}
