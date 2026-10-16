import CloudKit
import CoreData
import Foundation
import OSLog

/// The Settings flows live in `MembershipService`; the session forwards `MembershipManaging`
/// and keeps the share accept and the members refresh, which write its own state.
extension AppSession {
    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        try await membership.createFamilyInviteLink()
    }

    func revokeInviteLink() async {
        await membership.revokeInviteLink()
    }

    func renameActiveCart(_ rawName: String) async {
        await membership.renameActiveCart(rawName)
    }

    func removeMember(_ member: FamilyMember) async {
        await membership.removeMember(member)
    }

    func leaveCurrentFamily() async {
        await membership.leaveCurrentFamily()
    }

    var isLeavingSharedCart: Bool {
        membership.isLeavingSharedCart
    }

    func acceptPendingCloudKitShares() async {
        guard persistence.isLoaded else { return }
        let invitations = shareInbox.takeAll()
        guard !invitations.isEmpty else { return }
        beginBusyOperation()
        syncState = .syncing
        defer { endBusyOperation() }

        guard await acceptShareInvitations(invitations) else { return }

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

    /// Accepts the invitations not accepted yet. False when that failed: the invitations go back
    /// to the inbox for the next attempt and the failure shows.
    private func acceptShareInvitations(_ invitations: [PendingShareInvitation]) async -> Bool {
        let alreadyAccepted = invitations.allSatisfy { $0.participantStatus == .accepted }
        let toAccept = invitations.filter { $0.participantStatus != .accepted }
        guard !alreadyAccepted, !toAccept.isEmpty else {
            if alreadyAccepted {
                CartSyncLog.action.info("acceptShare skip alreadyAccepted")
            }
            return true
        }
        do {
            try await shareAccepter.acceptShareInvitations(toAccept)
        } catch {
            if alreadyJoinedMatchingShare(in: invitations),
                CloudKitUserFacingError.isBenignShareAcceptFailure(error)
            {
                CartSyncLog.action.info(
                    "acceptShare soft-success matchingShare error=\(error.localizedDescription, privacy: .public)"
                )
            } else {
                shareInbox.requeue(invitations)
                syncState = .failed
                lastSyncError = userFacingMessage(for: error)
                show(error)
                return false
            }
        }
        return true
    }

    private func alreadyJoinedMatchingShare(in invitations: [PendingShareInvitation]) -> Bool {
        let pendingShareNames = Set(invitations.map(\.shareRecordName))
        let pendingRootIDs = Set(invitations.compactMap(\.rootRecordID))
        for family in familySpaces where persistence.scope(for: family) == .shared {
            if let share = try? shareStore.fetchShare(for: family.objectID),
                pendingShareNames.contains(share.recordID.recordName)
            {
                return true
            }
            if let recordID = shareStore.recordID(for: family.objectID),
                pendingRootIDs.contains(recordID)
            {
                return true
            }
        }
        return false
    }

    func refreshFromServer() async {
        await syncCart(reason: .pull)
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
                familyMembers = try cloudSharing.familyMembers(
                    for: family,
                    account: account,
                    currentUserRecordName: currentUserRecordName
                )
                memberJoinNotifier.notifyNewMembersIfNeeded(
                    previousIDs: Set(previous.map(\.id)),
                    current: familyMembers,
                    accountID: account.id
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
