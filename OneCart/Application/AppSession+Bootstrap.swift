import Foundation

/// The startup order: the bootstrapper's store and sign-in steps return their outcome, and the
/// session applies each to its own state before the next.
extension AppSession {
    /// Restores the stored sign-in at launch, or shows Welcome when nobody is signed in.
    func bootstrapSession() async {
        guard let credential = await bootstrapper.restorableCredential() else {
            // No credential, or a revoked or unknown one: nobody is signed in (REQ-WIDGET-060).
            endShoppingTripWithoutAccount()
            showWelcome(.signIn)
            return
        }
        showWelcome(.connecting)
        await prepareSession(appleCredential: credential)
    }

    func retryWelcome() async {
        let previousPhase = welcomePhase
        if bootstrapper.willHardResetStores(for: previousPhase) {
            // The reset replaces the container; drop observers bound to the old coordinator
            // so `installCloudObservers()` registers against the new one.
            cloudSync.cancel()
        }
        guard let credential = appleSignIn.storedCredential() else {
            showWelcome(.signIn)
            return
        }
        showWelcome(.connecting)
        do {
            try bootstrapper.resetStoresIfArmed(previousPhase: previousPhase)
        } catch {
            showWelcome(.failed(userFacingMessage(for: error)))
            return
        }
        await prepareSession(appleCredential: credential)
    }

    /// Loads the stores, restores the account and sets up its cart. Any failure drops the
    /// half-restored account and shows the Welcome failure; only a store load arms the wipe.
    func prepareSession(appleCredential credential: AppleSignInCredential) async {
        let preferredName: String?
        switch await bootstrapper.loadStores(appleCredential: credential) {
        case let .loaded(name):
            preferredName = name
        case let .failed(error):
            failBootstrap(error)
            return
        }
        if !persistence.accountDeletionRecoveryRequired {
            installConnectivityMonitor()
            installCloudObservers()
        }
        do {
            let restored = try await bootstrapper.restoreAccount(
                appleCredential: credential,
                preferredName: preferredName
            )
            try await adoptRestoredAccount(restored)
            if persistence.accountDeletionRecoveryRequired {
                syncState = .failed
                finishWelcome()
                return
            }
            await acceptPendingCloudKitShares()
            try await finishFamilyCartSetup(for: restored)
            syncState = isOnline ? .synchronized : .offline
            await refreshFamilyMetadata(showErrors: false)
            finishWelcome()
            scheduleInviteLinkPreparation(delayNanoseconds: 2_000_000_000)
        } catch {
            failBootstrap(error)
        }
    }

    /// The session's account shows the device's name for the user; the carts unassigned on this
    /// device become the account's.
    private func adoptRestoredAccount(_ restored: OneCartAccount) async throws {
        account = OneCartAccount(
            id: restored.id,
            displayName: ParticipantDisplayName.displayOrPlaceholder(
                preferences: preferences,
                account: restored
            ),
            avatarURL: restored.avatarURL,
            bannerURL: restored.bannerURL
        )
        try await repository.claimUnassignedFamilySpaces(for: restored.id)
        try reload()
    }

    private func failBootstrap(_ error: Error) {
        clearBootstrapAccount()
        showWelcome(.failed(userFacingMessage(for: error)))
    }

    /// A failed startup signs nobody out: the cart state goes, a running trip stays for the
    /// retry (REQ-WIDGET-060).
    func clearBootstrapAccount() {
        clearAccountData(endingShoppingTrip: false)
        account = nil
    }
}
