import Foundation
import OSLog

/// `AccountDeletionService` deletes the account's data; the session guards the attempt and
/// applies its outcome to the session's own state.
extension AppSession {
    /// Permanently deletes the OneCart account: CloudKit private data, local stores, and SIWA session.
    func deleteAccount() async {
        guard account != nil else { return }
        guard !isDeletingAccount else {
            CartSyncLog.action.info("deleteAccount ignored duplicate")
            return
        }

        let plan = accountDeletion.plan()
        if plan.requiresNetwork, !online {
            presentAlert(String(localized: "account.delete_need_network"), kind: .error)
            return
        }

        isDeletingAccount = true
        beginBusyOperation()
        defer {
            isDeletingAccount = false
            endBusyOperation()
        }

        CartSyncLog.action.info("deleteAccount start")
        cloudSync.cancel()

        switch await accountDeletion.deleteAccountData(plan) {
        case .deleted:
            widgetSync.cancelDrain()
            finalizeSignOutAfterSuccessfulAccountDeletion()
            CartHaptics.success()
            CartSyncLog.action.info("deleteAccount done")
        case let .failed(error, didLeaveShared):
            await recoverAfterFailedAccountDeletion(didLeaveShared: didLeaveShared)
            presentAlert(accountDeletionFailureMessage(for: error), kind: .error)
        }
    }

    private func finalizeSignOutAfterSuccessfulAccountDeletion() {
        let deletedAccountID = account?.id
        if let deletedAccountID {
            defaults.removeObject(forKey: activeFamilyKey(accountID: deletedAccountID))
            memberJoinNotifier.clearSeenMembers(accountID: deletedAccountID)
            HouseholdCartCoordinator.clearKnownSharedFamilies(accountID: deletedAccountID, defaults: defaults)
            HouseholdCartCoordinator.clearPersonalCartKeys(accountID: deletedAccountID, defaults: defaults)
        }
        activityNotifier.clearSnapshots()
        forgetCurrentUserRecordName()
        preferences.participantDisplayName = ""
        appleSignIn.clearCredential()
        clearAccountData()
        account = nil
        dismissAlert()
        dismissSharedCartRemovedMessage()
        lastSyncError = nil
        syncState = .synchronized
        clearPreferredMainTab()
        showWelcome(.signIn)
        started = true
    }

    /// The service already put the local stores back; the session watches iCloud again and
    /// returns to the cart it had.
    private func recoverAfterFailedAccountDeletion(didLeaveShared: Bool) async {
        if !persistence.accountDeletionRecoveryRequired {
            cloudSync.installConnectivityMonitor()
            cloudSync.installCloudObservers()
        }
        syncState = .failed
        lastSyncError = String(localized: "account.delete_failed")
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
