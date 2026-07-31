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
        if persistence.inMemory {
            return OneCartAccount(
                id: OneCartStableID.uuid(for: "onecart.in-memory-user"),
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
        // Builder is nonisolated; keep a hard ceiling so Invite UI cannot spin forever
        // if `share` / `persistUpdatedShare` never calls back.
        return try await withThrowingTaskGroup(of: FamilyInviteLink.self) { group in
            group.addTask {
                try await FamilyInviteLinkBuilder.makeInviteLink(
                    persistence: persistence,
                    objectID: objectID,
                    displayName: displayName
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 22_000_000_000)
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
                    access: .owner,
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
            if $0.access != $1.access { return $0.access == .owner }
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
        share.removeParticipant(participant)
        let store = try persistence.store(for: .private)
        _ = try await persist(share, in: store)
    }

    func leaveFamily(_ family: FamilySpace) async throws {
        let objectID = family.objectID
        guard let share = try share(forObjectID: objectID) else {
            throw OneCartCloudKitError.familyNotShared
        }
        CartSyncLog.shareACL.info(
            "leaveFamily begin record=\(share.recordID.recordName, privacy: .public) env=\(CloudKitShareEnvironment.of(share).rawValue, privacy: .public)"
        )
        let sharedStore = try persistence.store(for: .shared)
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Void, Error>
        ) in
            persistence.container.purgeObjectsAndRecordsInZone(
                with: share.recordID.zoneID,
                in: sharedStore
            ) { _, error in
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
        if persistence.inMemory { return }
        guard let share = try share(forObjectID: objectID) else {
            CartSyncLog.shareACL.info("revokeInvite skip no-share")
            return
        }
        let shareEnv = CloudKitShareEnvironment.of(share)
        CartSyncLog.shareACL.info(
            "revokeInvite begin record=\(share.recordID.recordName, privacy: .public) shareEnv=\(shareEnv.rawValue, privacy: .public) process=\(CloudKitShareEnvironment.process.rawValue, privacy: .public) hasURL=\(share.url != nil)"
        )
        guard CloudKitShareEnvironment.canMutateInProcess(share) else {
            CartSyncLog.shareACL.error(
                "revokeInvite skip incompatible shareEnv=\(shareEnv.rawValue, privacy: .public) process=\(CloudKitShareEnvironment.process.rawValue, privacy: .public)"
            )
            return
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
                "revokeInvite persist soft-fail error=\(error.localizedDescription, privacy: .public)"
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


private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
