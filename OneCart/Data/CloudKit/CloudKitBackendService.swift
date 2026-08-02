import CloudKit
import CoreData
import Foundation

final class CloudKitBackendService {
    private let persistence: PersistenceController
    private let cloudContainer: CKContainer

    init(
        persistence: PersistenceController,
        cloudContainer: CKContainer? = nil
    ) {
        self.persistence = persistence
        self.cloudContainer = cloudContainer ?? CKContainer(
            identifier: PersistenceController.cloudKitContainerIdentifier
        )
    }

    func restoredAccount(
        appleUserID: String,
        displayName: String?
    ) async throws -> OneCartAccount {
        if persistence.inMemory || !persistence.cloudKitEnabled {
            let namespaceKey = persistence.inMemory
                ? "onecart.in-memory-user"
                : "apple:\(appleUserID)"
            return OneCartAccount(
                id: OneCartStableID.uuid(for: namespaceKey),
                displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
            )
        }

        let status = try await accountStatus()
        guard status == .available else {
            throw OneCartCloudKitError.accountUnavailable(status)
        }
        return OneCartAccount(
            id: OneCartStableID.uuid(for: "apple:\(appleUserID)"),
            displayName: displayName?.nilIfBlank ?? String(localized: "common.default_user")
        )
    }

    func access(for family: FamilySpace) -> FamilyAccess {
        persistence.scope(for: family) == .shared ? .member : .owner
    }

    func createFamilyInviteLink(for family: FamilySpace) async throws -> FamilyInviteLink {
        try await createFamilyInviteLink(
            objectID: family.objectID,
            displayName: family.displayName
        )
    }

    /// Prefer calling this after flushing the view context and reading `objectID` / name
    /// on the MainActor so CloudKit work does not hold the UI actor.
    func createFamilyInviteLink(
        objectID: NSManagedObjectID,
        displayName: String
    ) async throws -> FamilyInviteLink {
        if persistence.inMemory {
            return FamilyInviteLink(
                id: UUID(),
                familyName: displayName,
                url: URL(string: "https://www.icloud.com/share/onecart-preview")!
            )
        }

        let persistence = persistence
        // Ceiling must cover mirror wait (~8s) + share create (~12s) + door persist (~22s).
        // Nested persistShareRequired also uses 22s; outer must not cancel a mandatory reopen.
        return try await withThrowingTaskGroup(of: FamilyInviteLink.self) { group in
            group.addTask {
                try await FamilyInviteLinkBuilder.makeInviteLink(
                    persistence: persistence,
                    objectID: objectID,
                    displayName: displayName
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 45_000_000_000)
                throw OneCartCloudKitError.shareTimedOut
            }
            do {
                let link = try await group.next()!
                group.cancelAll()
                return link
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func familyMembers(for family: FamilySpace, account: OneCartAccount) throws -> [FamilyMember] {
        guard let share = try share(for: family) else {
            return [
                FamilyMember(
                    id: account.id,
                    displayName: account.displayName,
                    access: access(for: family),
                    joinedAt: family.createdDate,
                    isCurrentUser: true,
                    avatarURL: nil,
                    bannerURL: nil
                ),
            ]
        }

        let currentRecordName = share.currentUserParticipant?
            .userIdentity.userRecordID?.recordName
        return share.participants.compactMap { participant -> FamilyMember? in
            let recordName = participant.userIdentity.userRecordID?.recordName
                ?? participant.userIdentity.lookupInfo?.emailAddress
                ?? participant.userIdentity.lookupInfo?.phoneNumber
            guard let recordName, !recordName.isEmpty else { return nil }
            let name = participant.userIdentity.nameComponents.map {
                PersonNameComponentsFormatter.localizedString(
                    from: $0,
                    style: .default,
                    options: []
                )
            }?.nilIfBlank
            let isCurrent = recordName == currentRecordName
            let displayName: String = if isCurrent {
                account.displayName
            } else {
                name ?? String(localized: "common.default_member")
            }
            return FamilyMember(
                id: FamilyInviteLinkBuilder.stableUUID(for: recordName),
                displayName: displayName,
                access: participant.role == .owner ? .owner : .member,
                joinedAt: family.createdDate,
                isCurrentUser: isCurrent,
                avatarURL: nil,
                bannerURL: nil
            )
        }
        .sorted {
            if $0.access != $1.access {
                return $0.access == .owner
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func removeMember(_ member: FamilyMember, from family: FamilySpace) async throws {
        let objectID = family.objectID
        guard let share = try share(forObjectID: objectID) else {
            throw OneCartCloudKitError.familyNotShared
        }
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
                "removeMember skip incompatible shareEnv=\(CloudKitShareEnvironment.of(share).rawValue, privacy: .public) process=\(CloudKitShareEnvironment.process.rawValue, privacy: .public)"
            )
            throw OneCartCloudKitError.shareEnvironmentMismatch
        }
        guard let participant = share.participants.first(where: {
            let recordName = $0.userIdentity.userRecordID?.recordName
                ?? $0.userIdentity.lookupInfo?.emailAddress
            return recordName.map(FamilyInviteLinkBuilder.stableUUID(for:)) == member.id
        }) else {
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
    func leaveFamily(_ family: FamilySpace) async throws -> Bool {
        if persistence.inMemory {
            return true
        }

        let objectID = family.objectID
        let zoneID: CKRecordZone.ID
        if let share = try share(forObjectID: objectID) {
            CartSyncLog.shareACL.info(
                "leaveFamily begin record=\(share.recordID.recordName, privacy: .public) env=\(CloudKitShareEnvironment.of(share).rawValue, privacy: .public)"
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
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Void, Error>
        ) in
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

    @discardableResult
    func ensureReadWriteACL(for family: FamilySpace) async throws -> Bool {
        guard let share = try share(for: family) else { return false }
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
                "ensureReadWriteACL skip incompatible shareEnv=\(CloudKitShareEnvironment.of(share).rawValue, privacy: .public) process=\(CloudKitShareEnvironment.process.rawValue, privacy: .public)"
            )
            return false
        }
        var needsPersist = false
        if OneCartShareLinkJoin.applyReadWriteACL(to: share) {
            needsPersist = true
        }
        if OneCartShareBranding.apply(to: share) {
            needsPersist = true
        }
        guard needsPersist else { return false }
        let store = try persistence.store(for: .private)
        _ = try await persist(share, in: store)
        return true
    }

    func revokeInviteLink(_ family: FamilySpace) async throws {
        try await revokeInviteLink(objectID: family.objectID)
    }

    func revokeInviteLink(objectID: NSManagedObjectID) async throws {
        if persistence.inMemory {
            return
        }
        guard let share = try share(forObjectID: objectID) else {
            CartSyncLog.shareACL.info("revokeInvite skip no-share")
            throw OneCartCloudKitError.familyNotShared
        }
        let shareEnv = CloudKitShareEnvironment.of(share)
        CartSyncLog.shareACL.info(
            "revokeInvite begin record=\(share.recordID.recordName, privacy: .public) shareEnv=\(shareEnv.rawValue, privacy: .public) process=\(CloudKitShareEnvironment.process.rawValue, privacy: .public) hasURL=\(share.url != nil)"
        )
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
                "revokeInvite skip incompatible shareEnv=\(shareEnv.rawValue, privacy: .public) process=\(CloudKitShareEnvironment.process.rawValue, privacy: .public)"
            )
            throw OneCartCloudKitError.shareEnvironmentMismatch
        }
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

    func stopSharing(_ family: FamilySpace) async throws {
        try await stopSharing(objectID: family.objectID)
    }

    func stopSharing(objectID: NSManagedObjectID) async throws {
        try await revokeInviteLink(objectID: objectID)
    }

    private func share(for family: FamilySpace) throws -> CKShare? {
        try share(forObjectID: family.objectID)
    }

    private func share(forObjectID objectID: NSManagedObjectID) throws -> CKShare? {
        try persistence.container.fetchShares(matching: [objectID])[objectID]
    }

    private func persist(
        _ share: CKShare,
        in store: NSPersistentStore,
        timeoutNanoseconds: UInt64 = 22_000_000_000
    ) async throws -> CKShare {
        try await withThrowingTaskGroup(of: CKShare.self) { group in
            group.addTask {
                try await self.persistWithoutTimeout(share, in: store)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw OneCartCloudKitError.shareTimedOut
            }
            do {
                let saved = try await group.next()!
                group.cancelAll()
                return saved
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func persistWithoutTimeout(
        _ share: CKShare,
        in store: NSPersistentStore
    ) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            persistence.container.persistUpdatedShare(share, in: store) { savedShare, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let savedShare {
                    continuation.resume(returning: savedShare)
                } else {
                    continuation.resume(throwing: OneCartCloudKitError.shareURLUnavailable)
                }
            }
        }
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            cloudContainer.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
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


private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
