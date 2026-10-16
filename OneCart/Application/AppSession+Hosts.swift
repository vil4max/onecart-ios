import Foundation

extension AppSession: CartRefreshing {
    func healOwnerShareACL() async {
        guard let family = activeFamilySpace else { return }
        await shareOrchestrator.ensureOwnerReadWriteACL(for: family, isOwner: access?.isOwner == true)
    }

    func hardRefreshCart() async throws {
        try CartSyncService.resetViewContextAndRefetch(persistence: persistence) {
            try reload()
        }
    }

    var cartPurchaseCounts: (purchased: Int, total: Int) {
        (products.filter(\.isPurchasedValue).count, products.count)
    }

    func handleInviteeSharedCartGone() async {
        await household.handleInviteeSharedCartGoneIfNeeded()
    }
}

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
        presentAlert(message, kind: .error)
    }

    func softRefreshCartProducts() {
        do {
            let previous = Self.activitySnapshots(of: products)
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
            let purchasedCount = products.filter(\.isPurchasedValue).count
            let totalCount = products.count
            CartSyncLog.cart.info(
                "softRefresh purchased=\(purchasedCount)/\(totalCount)"
            )
            let current = Self.activitySnapshots(of: products)
            if let cartID = activeFamilySpace?.id {
                let currentUserName = Self.participantName(preferences: preferences, account: account) ?? ""
                let isShared = familyMembers.count > 1
                activityNotifier.notifyIfNeeded(
                    cartID: cartID,
                    previous: previous,
                    current: current,
                    currentUserName: currentUserName,
                    isSharedCart: isShared
                )
            }
        } catch {
            CartSyncLog.cart.error(
                "softRefresh failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func applyConnectivityOnline(_ isOnline: Bool) {
        online = isOnline
    }

    /// Rows without an id are skipped: no identity survives between two snapshots for them, so
    /// they would read as removed and re-added on every refresh and notify the family.
    static func activitySnapshots(of products: [ProductEntity]) -> [CartItemSnapshot] {
        products.compactMap { product in
            product.id.map { id in
                CartItemSnapshot(
                    id: id,
                    name: product.displayName,
                    isPurchased: product.isPurchasedValue,
                    createdByName: product.createdByName,
                    purchasedByName: product.purchasedByName
                )
            }
        }
    }
}

extension AppSession: SessionBootstrapHost {
    /// Bootstrap resets the persistent stores under the live fetch results; bumping the
    /// revision is the observable signal dependents (`ShoppingListView`) react to.
    func notifyBootstrapObjectWillChange() {
        cartSync.bumpRevisionAfterLocalChange()
    }

    func reloadAfterBootstrap() throws {
        try reload()
    }

    func applyBootstrapAccount(_ account: OneCartAccount) {
        self.account = account
    }

    func clearBootstrapAccount() {
        clearAccountData(endingShoppingTrip: false)
        account = nil
    }

    func applyBootstrapSyncState(_ state: OneCartSyncState) {
        syncState = state
    }

    func applyWelcomeSignIn() {
        showWelcome(.signIn)
    }

    func applyWelcomeConnecting() {
        showWelcome(.connecting)
    }

    func applyWelcomeFailed(_ message: String) {
        showWelcome(.failed(message))
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
