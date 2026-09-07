import CoreData
import Foundation

extension AppSession {
    func updateWidgetSnapshot(
        themeOverride: AppTheme? = nil,
        accentOverride: AppAccentColor? = nil
    ) {
        let activeTheme = themeOverride ?? preferences.theme
        let activeAccent = accentOverride ?? preferences.accentColor
        guard isReady, let list = activeLists.first ?? lists.first else {
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
            WidgetSnapshotStore.shared.save(snapshot: emptySnapshot)
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
            items: itemSnapshots
        )

        WidgetSnapshotStore.shared.save(snapshot: snapshot)
    }

    func drainWidgetPendingToggles() async {
        let pendingIDs = WidgetSnapshotStore.shared.drainPendingToggles()
        guard !pendingIDs.isEmpty else { return }

        for id in pendingIDs {
            if let product = products.first(where: { $0.id == id }) {
                await togglePurchased(product)
            }
        }
        updateWidgetSnapshot()
    }
}
