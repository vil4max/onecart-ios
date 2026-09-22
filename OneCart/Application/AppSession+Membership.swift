import CloudKit
import CoreData
import Foundation
import OSLog

extension AppSession {
    func revokeInviteLink() async {
        guard account != nil,
              let family = activeFamilySpace,
              access?.isOwner == true
        else {
            CartSyncLog.action.error("revokeInvite denied missingOwnerOrFamily")
            return
        }
        guard online else {
            CartSyncLog.action.error("revokeInvite denied offline")
            presentAlert(String(localized: "alert.revoke_invite_need_network"), kind: .error)
            return
        }
        CartSyncLog.action.info("revokeInvite session begin")
        beginBusyOperation()
        defer { endBusyOperation() }
        do {
            try await shareOrchestrator.revokeInviteLink(for: family)
            clearPreparedInviteLink()
            await refreshFamilyMetadata(showErrors: false)
            CartSyncLog.action.info("revokeInvite session done")
            presentAlert(String(localized: "account.revoke_invite_done"), kind: .success)
        } catch {
            CartSyncLog.action.error(
                "revokeInvite session fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func renameActiveCart(_ rawName: String) async {
        guard let family = activeFamilySpace,
              let familyID = family.id,
              access?.isOwner == true
        else { return }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        beginBusyOperation()
        defer { endBusyOperation() }
        do {
            try await repository.renameFamilySpace(id: familyID, name: trimmed)
            try reload(preferredFamilySpaceID: familyID)
            clearPreparedInviteLink()
            scheduleInviteLinkPreparation()
            CartHaptics.success()
        } catch {
            show(error)
        }
    }

    func acceptPendingCloudKitShares() async {
        guard persistence.isLoaded else { return }
        let metadata = AppDelegate.takePendingShareMetadata()
        guard !metadata.isEmpty else { return }
        beginBusyOperation()
        syncState = .syncing
        defer { endBusyOperation() }

        let alreadyAccepted = metadata.allSatisfy { $0.participantStatus == .accepted }
        let toAccept = metadata.filter { $0.participantStatus != .accepted }

        if !alreadyAccepted, !toAccept.isEmpty {
            do {
                try await persistence.acceptShareInvitations(from: toAccept)
            } catch {
                if alreadyJoinedMatchingShare(in: metadata),
                   CloudKitUserFacingError.isBenignShareAcceptFailure(error)
                {
                    CartSyncLog.action.info(
                        "acceptShare soft-success matchingShare error=\(error.localizedDescription, privacy: .public)"
                    )
                } else {
                    AppDelegate.requeue(metadata)
                    syncState = .failed
                    lastSyncError = userFacingMessage(for: error)
                    show(error)
                    return
                }
            }
        } else if alreadyAccepted {
            CartSyncLog.action.info("acceptShare skip alreadyAccepted")
        }

        syncState = .synchronized
        do {
            try reload()
            if let account {
                try await offerSharedCartJoinIfNeeded(for: account)
                await refreshFamilyMetadata(showErrors: false)
                scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
            }
            CartHaptics.success()
        } catch {
            syncState = .failed
            lastSyncError = userFacingMessage(for: error)
            show(error)
        }
        cloudSync.scheduleCloudReload(delayNanoseconds: 350_000_000)
    }

    func removeMember(_ member: FamilyMember) async {
        guard let family = activeFamilySpace,
              access?.isOwner == true,
              !member.isCurrentUser else { return }
        guard online else {
            presentAlert(String(localized: "alert.members_need_network"), kind: .error)
            return
        }

        CartSyncLog.action.info("removeMember start id=\(member.id.uuidString, privacy: .public)")
        beginBusyOperation()
        defer { endBusyOperation() }
        do {
            try await backend.removeMember(member, fromFamily: family.objectID)
            await refreshFamilyMetadata(showErrors: false)
            CartHaptics.success()
            CartSyncLog.action.info("removeMember done")
        } catch {
            CartSyncLog.action.error(
                "removeMember fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func leaveCurrentFamily() async {
        guard let account,
              let family = activeFamilySpace,
              access?.isParticipant == true else { return }
        let familyID = family.id

        CartSyncLog.action.info(
            "leaveFamily start family=\(familyID?.uuidString ?? "-", privacy: .public)"
        )
        beginBusyOperation()
        defer { endBusyOperation() }
        do {
            let discardLeftovers = try await backend.leaveFamily(objectID: family.objectID)
            if discardLeftovers, let familyID {
                do {
                    try await repository.discardLocalSharedFamilySpace(id: familyID)
                } catch let error as RepositoryError where error == .familySpaceNotFound {
                    CartSyncLog.action.info("leaveFamily local shared already gone")
                }
            }
            try await household.reactivatePersonalCartIfNeeded(for: account)
            lastActiveFamilyWasShared = false
            await refreshFamilyMetadata(showErrors: false)
            CartHaptics.success()
            CartSyncLog.action.info("leaveFamily done")
        } catch {
            CartSyncLog.action.error(
                "leaveFamily fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
            if case OneCartCloudKitError.leaveTimedOut = error {
                lastActiveFamilyWasShared = true
                Task { await recoverAfterLeaveTimeout() }
            }
        }
    }

    private func alreadyJoinedMatchingShare(in metadata: [CKShare.Metadata]) -> Bool {
        let pendingShareNames = Set(metadata.map(\.share.recordID.recordName))
        let pendingRootIDs = Set(metadata.compactMap(\.hierarchicalRootRecordID))
        for family in familySpaces where persistence.scope(for: family) == .shared {
            if let share = try? persistence.container.fetchShares(matching: [family.objectID])[family.objectID],
               pendingShareNames.contains(share.recordID.recordName)
            {
                return true
            }
            if let recordID = persistence.container.recordID(for: family.objectID),
               pendingRootIDs.contains(recordID)
            {
                return true
            }
        }
        return false
    }

    private func recoverAfterLeaveTimeout() async {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for _ in 0 ..< 8 {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if await self.attemptLeaveRecoveryPass() {
                        return true
                    }
                }
                return false
            }
            group.addTask {
                for await _ in NotificationCenter.default.notifications(
                    named: .oneCartDidFinishLateLeavePurge
                ) where await self.attemptLeaveRecoveryPass() {
                    return true
                }
                return false
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func attemptLeaveRecoveryPass() async -> Bool {
        do {
            try reload()
            await household.handleInviteeSharedCartGoneIfNeeded()
        } catch {
            CartSyncLog.action.error(
                "leaveFamily recovery reload fail error=\(error.localizedDescription, privacy: .public)"
            )
        }
        let hasShared = familySpaces.contains { persistence.scope(for: $0) == .shared }
        if !hasShared {
            CartSyncLog.action.info("leaveFamily recovery shared gone")
        }
        return !hasShared
    }

    func refreshFromServer() async {
        await syncCart(reason: .pull)
    }

    func showFamilyManagement() {
        preferredMainTab = .account
        Task { await refreshFamilyMetadata(showErrors: true) }
    }

    func refreshAccountSharing() async {
        await refreshFamilyMetadata(showErrors: false)
    }

    func refreshFamilyMetadata(showErrors: Bool) async {
        guard let account else { return }
        // A local write that syncs later, so it does not wait for connectivity.
        schedulePublishMemberProfile()
        guard online else { return }
        #if DEBUG
            if DemoUIMode.isEnabled, DemoUIMode.role == .member, !familyMembers.isEmpty {
                return
            }
        #endif
        isFamilyMetadataLoading = true
        defer { isFamilyMetadataLoading = false }
        do {
            if let family = activeFamilySpace {
                let previous = familyMembers
                familyMembers = try backend.familyMembers(
                    for: family,
                    account: account,
                    currentUserRecordName: currentUserRecordName
                )
                MemberJoinNotifier.notifyNewMembersIfNeeded(
                    previousIDs: Set(previous.map(\.id)),
                    current: familyMembers,
                    accountID: account.id,
                    defaults: defaults
                )
                // The widget names a partner; a synced profile can rename one without a reload.
                if familyMembers != previous {
                    updateWidgetSnapshot()
                }
            } else {
                familyMembers = []
            }
        } catch {
            if showErrors {
                show(error)
            }
        }
    }
}
