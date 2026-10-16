import Foundation

/// The session as the cart sync's refresher and as the coordinators' context, and where it
/// applies what they report.
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
        if case let .failed(error) = await household.handleInviteeSharedCartGoneIfNeeded() {
            show(error)
        }
    }
}

extension AppSession: HouseholdCartContext {
    var isEnsuringHouseholdCart: Bool {
        household.isEnsuringHouseholdCart
    }

    var householdCartBootstrapFailed: Bool {
        household.householdCartBootstrapFailed
    }

    var isReconcilingPersonalCart: Bool {
        household.isReconcilingPersonalCart
    }

    var lastActiveFamilyWasShared: Bool {
        household.lastActiveFamilyWasShared
    }

    var sharedCartRemovedMessage: String? {
        household.sharedCartRemovedMessage
    }
}

extension AppSession: CloudSyncContext {
    func applyCloudSyncEvent(_ event: CloudSyncEvent) {
        switch event {
        case .importStarted, .reconnected:
            syncState = .syncing
        case let .importFailed(error):
            syncState = CloudKitUserFacingError.isNetworkError(error) ? .offline : .failed
            let message = userFacingMessage(for: error)
            lastSyncError = message
            if CloudKitUserFacingError.isProductionSchemaFailure(error) {
                presentProductionSchemaAlertIfNeeded(message)
            }
        case .importFinished:
            syncState = isOnline ? .synchronized : .offline
            lastSyncError = nil
        case let .connectivityChanged(isOnline):
            online = isOnline
        case .wentOffline:
            syncState = .offline
        }
    }

    /// Applies how a cart sync ended; a success refreshes the members first.
    func applyCloudSyncResult(_ result: CloudSyncResult?) async {
        switch result {
        case .synced:
            await refreshFamilyMetadata(showErrors: false)
            syncState = isOnline ? .synchronized : .offline
            lastSyncError = nil
        case let .failed(message, presentsAlert):
            lastSyncError = message
            syncState = .failed
            if presentsAlert {
                presentAlert(message, kind: .error)
            }
        case nil:
            break
        }
    }

    func runCloudImportPass(for account: OneCartAccount) async {
        softRefreshCartProducts()
        do {
            try await offerSharedCartJoinIfNeeded(for: account)
        } catch {
            // Keep importing CloudKit changes even if adopt/merge races.
            syncState = .failed
            lastSyncError = userFacingMessage(for: error)
        }
        await drainWidgetPendingToggles()
        await applyCloudSyncResult(await cloudSync.syncCart(reason: .cloudImport))
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
            if let cartID = activeFamilySpace?.id {
                activityNotifier.notifyIfNeeded(
                    cartID: cartID,
                    previous: previous,
                    current: Self.activitySnapshots(of: products),
                    currentUserName: participantName ?? "",
                    isSharedCart: familyMembers.count > 1
                )
            }
        } catch {
            CartSyncLog.cart.error(
                "softRefresh failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
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
