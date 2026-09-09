import CoreData
import Foundation

extension AppSession {
    func updateWidgetSnapshot(
        themeOverride: AppTheme? = nil,
        accentOverride: AppAccentColor? = nil
    ) {
        let activeTheme = themeOverride ?? preferences.theme
        let activeAccent = accentOverride ?? preferences.accentColor
        guard isReady, let accountID = account?.id, let familyID = activeFamilySpace?.id,
              let list = activeLists.first ?? lists.first
        else {
            let emptySnapshot = WidgetCartSnapshot(
                cartTitle: "OneCart Family",
                totalCount: 0,
                purchasedCount: 0,
                isSyncing: false,
                lastUpdated: Date(),
                familyMemberCount: 1,
                activePartnerName: nil,
                themeRaw: activeTheme.rawValue,
                accentColorRaw: activeAccent.rawValue,
                items: []
            )
            widgetStore.save(snapshot: emptySnapshot)
            return
        }

        let allProducts = products(inListID: list.id ?? UUID())
        let unpurchased = allProducts.filter { !$0.isPurchasedValue }
        let purchased = allProducts.filter(\.isPurchasedValue)
        let totalCount = allProducts.count
        let purchasedCount = purchased.count

        // Display up to 6 unpurchased items, followed by up to 2 purchased items
        let displayProducts: [ProductEntity] = Array(unpurchased.prefix(6)) + Array(purchased.prefix(2))

        let itemSnapshots = displayProducts.compactMap { product -> WidgetItemSnapshot? in
            guard let id = product.id else { return nil }
            let name = product.displayName
            let isPurchased = product.isPurchasedValue
            let categoryRaw = product.categoryValue.rawValue
            let subtitle: String? = {
                if isPurchased, let buyer = product.purchasedByName, !buyer.isEmpty {
                    return String(localized: "cart.in_trolley_by \(buyer)")
                }
                if let adder = product.createdByName, !adder.isEmpty {
                    return String(localized: "cart.added_by \(adder)")
                }
                return nil
            }()

            return WidgetItemSnapshot(
                id: id,
                name: name,
                isPurchased: isPurchased,
                categoryRaw: categoryRaw,
                subtitle: subtitle
            )
        }

        let partnerName: String? = {
            if familyMembers.count > 1, let other = familyMembers.first(where: { !$0.isCurrentUser }) {
                return other.displayName
            }
            return nil
        }()

        let snapshot = WidgetCartSnapshot(
            cartTitle: cartTitle,
            totalCount: totalCount,
            purchasedCount: purchasedCount,
            isSyncing: isCartSyncing,
            lastUpdated: Date(),
            familyMemberCount: max(1, familyMembers.count),
            activePartnerName: partnerName,
            themeRaw: activeTheme.rawValue,
            accentColorRaw: activeAccent.rawValue,
            accountID: accountID,
            familyID: familyID,
            items: itemSnapshots
        )

        widgetStore.save(snapshot: snapshot)
    }

    func drainWidgetPendingToggles() async {
        do {
            try await applyPendingWidgetPurchases()
        } catch {
            show(error)
        }
    }

    func performWidgetPurchase(_ request: WidgetPurchaseRequest) async throws {
        await start()
        guard account?.id == request.accountID, activeFamilySpace?.id == request.familyID, canEdit else {
            throw WidgetPurchaseError.unavailable
        }
        try widgetStore.enqueuePurchase(request)
        while try widgetStore.pendingPurchases().contains(where: { $0.id == request.id }) {
            try Task.checkCancellation()
            guard account?.id == request.accountID, activeFamilySpace?.id == request.familyID, canEdit else {
                throw WidgetPurchaseError.unavailable
            }
            do {
                try await applyPendingWidgetPurchases()
            } catch {
                if try widgetStore.pendingPurchases().contains(where: { $0.id == request.id }) {
                    throw error
                }
            }
        }
    }

    private func applyPendingWidgetPurchases() async throws {
        if let widgetDrainTask {
            try await widgetDrainTask.value
            return
        }
        guard account != nil, activeFamilySpace != nil else { return }
        let task = Task { @MainActor in
            defer {
                widgetDrainTask = nil
                updateWidgetSnapshot()
            }
            var blockedProductIDs = Set<UUID>()
            var firstError: Error?
            for request in try widgetStore.pendingPurchases() {
                guard account?.id == request.accountID, activeFamilySpace?.id == request.familyID else { continue }
                guard !blockedProductIDs.contains(request.productID) else { continue }
                do {
                    try await persistWidgetPurchase(request)
                } catch {
                    // Preserve order for this product without blocking unrelated purchases.
                    blockedProductIDs.insert(request.productID)
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            if let firstError {
                throw firstError
            }
        }
        widgetDrainTask = task
        try await task.value
    }

    private func persistWidgetPurchase(_ request: WidgetPurchaseRequest) async throws {
        guard account?.id == request.accountID, activeFamilySpace?.id == request.familyID, canEdit else {
            throw WidgetPurchaseError.unavailable
        }
        pendingCartMutationCount += 1
        defer { finishCartMutation() }
        try await repository.setPurchased(
            id: request.productID,
            familySpaceID: request.familyID,
            isPurchased: request.isPurchased,
            participantDisplayName: Self.participantName(preferences: preferences, account: account),
            purchasedAt: request.createdAt
        )
        // A crash after save leaves an idempotent desired-state command available for retry.
        try widgetStore.acknowledgePurchase(id: request.id)
        if account?.id == request.accountID, activeFamilySpace?.id == request.familyID {
            try reload(preferredFamilySpaceID: request.familyID)
            cartSync.bumpRevisionAfterLocalChange()
        }
    }
}
