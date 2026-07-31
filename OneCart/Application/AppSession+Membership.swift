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
        isBusy = true
        defer { isBusy = false }
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
        isBusy = true
        defer { isBusy = false }
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
        isBusy = true
        syncState = .syncing
        defer { isBusy = false }
        do {
            try await persistence.acceptShareInvitations(from: metadata)
        } catch {
            AppDelegate.requeue(metadata)
            syncState = .failed
            lastSyncError = userFacingMessage(for: error)
            show(error)
            return
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
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.removeMember(member, from: family)
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
        guard online else {
            presentAlert(String(localized: "alert.leave_need_network"), kind: .error)
            return
        }

        CartSyncLog.action.info(
            "leaveFamily start family=\(family.id?.uuidString ?? "-", privacy: .public)"
        )
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.leaveFamily(family)
            try await household.reactivatePersonalCartIfNeeded(for: account)
            await refreshFamilyMetadata(showErrors: false)
            CartHaptics.success()
            CartSyncLog.action.info("leaveFamily done")
        } catch {
            CartSyncLog.action.error(
                "leaveFamily fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
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
        guard let account, online else { return }
        isFamilyMetadataLoading = true
        defer { isFamilyMetadataLoading = false }
        do {
            if let family = activeFamilySpace {
                let previousIDs = Set(familyMembers.map(\.id))
                familyMembers = try backend.familyMembers(for: family, account: account)
                MemberJoinNotifier.notifyNewMembersIfNeeded(
                    previousIDs: previousIDs,
                    current: familyMembers,
                    accountID: account.id,
                    defaults: defaults
                )
            } else {
                familyMembers = []
            }
        } catch {
            if showErrors { show(error) }
        }
    }
}
