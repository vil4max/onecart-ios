import CloudKit
import CoreData
import Foundation
import OSLog

extension AppSession {
    func deleteCurrentCartAndStartFresh() async {
        guard let account,
              let family = activeFamilySpace,
              access?.isOwner == true
        else {
            CartSyncLog.action.error("deleteCart denied missingOwnerOrFamily")
            return
        }
        guard online else {
            CartSyncLog.action.error("deleteCart denied offline")
            presentAlert(String(localized: "alert.delete_cart_need_network"))
            return
        }
        CartSyncLog.action.info("deleteCart session begin")
        isBusy = true
        defer { isBusy = false }
        do {
            let cartName = Self.householdCartName(for: account)
            let newID = try await shareOrchestrator.deleteCurrentCartAndStartFresh(
                family: family,
                accountID: account.id,
                defaultFamilyName: cartName
            )
            clearPreparedInviteLink()
            defaults.set(newID.uuidString, forKey: activeFamilyKey(accountID: account.id))
            try reload(preferredFamilySpaceID: newID)
            await refreshFamilyMetadata(showErrors: false)
            scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
            CartSyncLog.action.info("deleteCart session done")
            presentAlert(String(localized: "account.recreate_cart_done \(cartName)"))
        } catch {
            CartSyncLog.action.error(
                "deleteCart session fail error=\(error.localizedDescription, privacy: .public)"
            )
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

        // Share accept already succeeded — do not requeue metadata if local adopt/reload
        // races (shared lists still importing, temporary merge permission deny).
        // Always consolidate into the accepted/newest shared cart (merge private +
        // archive stale guest shares from previous cart versions).
        syncState = .synchronized
        do {
            try reload()
            if let account {
                try await offerSharedCartJoinIfNeeded(for: account)
                await refreshFamilyMetadata(showErrors: false)
                scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
            }
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
            presentAlert(String(localized: "alert.members_need_network"))
            return
        }

        CartSyncLog.action.info("removeMember start id=\(member.id.uuidString, privacy: .public)")
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.removeMember(member, from: family)
            await refreshFamilyMetadata(showErrors: false)
            CartSyncLog.action.info("removeMember done")
        } catch {
            CartSyncLog.action.error(
                "removeMember fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func leaveCurrentFamily() async {
        guard account != nil,
              let family = activeFamilySpace,
              access?.isParticipant == true else { return }
        guard online else {
            presentAlert(String(localized: "alert.leave_need_network"))
            return
        }

        CartSyncLog.action.info(
            "leaveFamily start family=\(family.id?.uuidString ?? "-", privacy: .public)"
        )
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.leaveFamily(family)
            cloudSync.scheduleCloudReload(delayNanoseconds: 350_000_000)
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
                familyMembers = try backend.familyMembers(for: family, account: account)
            } else {
                familyMembers = []
            }
        } catch {
            if showErrors { show(error) }
        }
    }
}
