import Foundation
import OSLog

extension AppSession {
    /// Permanently deletes the OneCart account: CloudKit private data, local stores, and SIWA session.
    /// Shared carts owned by this user are removed with the private zone. Member carts stay for others.
    func deleteAccount() async {
        guard account != nil else { return }
        guard !isDeletingAccount else {
            CartSyncLog.action.info("deleteAccount ignored duplicate")
            return
        }

        let requiresCloud = persistence.cloudKitEnabled
        if requiresCloud, !online {
            presentAlert(String(localized: "account.delete_need_network"), kind: .error)
            return
        }

        isDeletingAccount = true
        isBusy = true
        defer {
            isDeletingAccount = false
            isBusy = false
        }

        CartSyncLog.action.info("deleteAccount start")
        cloudSync.cancel()

        var didLeaveShared = false
        var didDetachLocalStores = false
        var didDeleteCloudData = false
        do {
            didLeaveShared = try await leaveSharedCartIfParticipantForDeletion()
            // Drop published cart state before unloading stores; keep account + SIWA until cloud succeeds.
            clearAccountData()
            try await accountLocalStorePreparer.detachLocalStoresForCloudAccountDeletion()
            didDetachLocalStores = true
            try await accountCloudDataDeleter.deletePrivateAccountCloudData()
            didDeleteCloudData = true
            do {
                try await accountLocalStorePreparer.attachEmptyLocalStoresAfterCloudAccountDeletion()
            } catch {
                CartSyncLog.action.error(
                    "deleteAccount attachEmpty after cloud success " +
                        "error=\(error.localizedDescription, privacy: .public)"
                )
            }
            finalizeSignOutAfterSuccessfulAccountDeletion()
            CartHaptics.success()
            CartSyncLog.action.info("deleteAccount done")
        } catch {
            CartSyncLog.action.error(
                "deleteAccount fail error=\(error.localizedDescription, privacy: .public)"
            )
            if didDeleteCloudData {
                try? await accountLocalStorePreparer.attachEmptyLocalStoresAfterCloudAccountDeletion()
                finalizeSignOutAfterSuccessfulAccountDeletion()
                CartHaptics.success()
                CartSyncLog.action.info("deleteAccount completed after attach recovery")
                return
            }
            await recoverAfterFailedAccountDeletion(
                didLeaveShared: didLeaveShared,
                didDetachLocalStores: didDetachLocalStores
            )
            presentAlert(accountDeletionFailureMessage(for: error), kind: .error)
        }
    }

    @discardableResult
    private func leaveSharedCartIfParticipantForDeletion() async throws -> Bool {
        guard access?.isParticipant == true,
              let family = activeFamilySpace,
              let familyID = family.id
        else { return false }

        CartSyncLog.action.info(
            "deleteAccount leaveShared family=\(familyID.uuidString, privacy: .public)"
        )
        let discardLeftovers = try await backend.leaveFamily(family)
        if discardLeftovers {
            do {
                try await repository.discardLocalSharedFamilySpace(id: familyID)
            } catch let error as RepositoryError where error == .familySpaceNotFound {
                CartSyncLog.action.info("deleteAccount leaveShared local already gone")
            }
        }
        lastActiveFamilyWasShared = false
        return true
    }

    private func finalizeSignOutAfterSuccessfulAccountDeletion() {
        let deletedAccountID = account?.id
        if let deletedAccountID {
            defaults.removeObject(forKey: activeFamilyKey(accountID: deletedAccountID))
            MemberJoinNotifier.clearSeenMembers(accountID: deletedAccountID, defaults: defaults)
        }
        preferences.participantDisplayName = ""
        appleSignIn.clearCredential()
        clearAccountData()
        account = nil
        userAlert = nil
        sharedCartRemovedMessage = nil
        lastSyncError = nil
        syncState = .synchronized
        preferredMainTab = nil
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
        started = true
    }

    private func recoverAfterFailedAccountDeletion(
        didLeaveShared: Bool,
        didDetachLocalStores: Bool
    ) async {
        if didDetachLocalStores {
            try? await accountLocalStorePreparer.attachEmptyLocalStoresAfterCloudAccountDeletion()
        }
        cloudSync.installConnectivityMonitor()
        cloudSync.installCloudObservers()
        guard let account else { return }
        try? reload()
        if didLeaveShared {
            try? await household.reactivatePersonalCartIfNeeded(for: account)
        }
    }

    private func accountDeletionFailureMessage(for error: Error) -> String {
        if let cloudKitError = error as? OneCartCloudKitError,
           case .accountUnavailable = cloudKitError
        {
            return userFacingMessage(for: error)
        }
        return String(localized: "account.delete_failed")
    }
}
