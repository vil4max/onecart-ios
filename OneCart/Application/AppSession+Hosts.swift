import Foundation

extension AppSession: HouseholdCartHost {
    func applyEnsuringHouseholdCart(_ value: Bool) {
        isEnsuringHouseholdCart = value
    }

    func applyHouseholdCartBootstrapFailed(_ value: Bool) {
        householdCartBootstrapFailed = value
    }

    func reloadHousehold(preferredFamilySpaceID: UUID?) throws {
        try reload(preferredFamilySpaceID: preferredFamilySpaceID)
    }

    func presentHouseholdError(_ error: Error) {
        show(error)
    }

    func scheduleInviteLinkPreparation() {
        scheduleInviteLinkPreparation(delayNanoseconds: 1_500_000_000)
    }

    func householdDisplayName(for account: OneCartAccount) -> String {
        Self.householdCartName(for: account)
    }
}

extension AppSession: CloudSyncHost {
    func applySyncState(_ state: OneCartSyncState) {
        syncState = state
    }

    func applyLastSyncError(_ message: String?) {
        lastSyncError = message
    }

    func presentSyncAlert(_ message: String) {
        presentAlert(message)
    }

    func softRefreshCartProducts() {
        do {
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.cart.info(
                "softRefresh purchased=\(self.products.filter(\.isPurchasedValue).count)/\(self.products.count)"
            )
        } catch {
            CartSyncLog.cart.error(
                "softRefresh failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func applyConnectivityOnline(_ isOnline: Bool) {
        online = isOnline
    }
}

extension AppSession: SessionBootstrapHost {
    func notifyBootstrapObjectWillChange() {
        objectWillChange.send()
    }

    func reloadAfterBootstrap() throws {
        try reload()
    }

    func applyBootstrapAccount(_ account: OneCartAccount) {
        self.account = account
    }

    func clearBootstrapAccount() {
        clearAccountData()
        account = nil
    }

    func applyBootstrapSyncState(_ state: OneCartSyncState) {
        syncState = state
    }

    func applyWelcomeSignIn() {
        needsWelcome = true
        welcomePhase = .signIn
        isReady = true
    }

    func applyWelcomeConnecting() {
        needsWelcome = true
        welcomePhase = .connecting
        isReady = true
    }

    func applyWelcomeFailed(_ message: String) {
        needsWelcome = true
        welcomePhase = .failed(message)
        isReady = true
    }

    func applyWelcomeReady(needsWelcome: Bool) {
        self.needsWelcome = needsWelcome
        if !needsWelcome {
            welcomePhase = .signIn
        }
        isReady = true
    }

    func clearStoredAppleCredential() {
        appleSignIn.clearCredential()
    }
}

