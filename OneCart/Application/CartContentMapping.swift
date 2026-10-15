import Foundation

// Entity → value mapping for the screens' snapshots. Only `CartContentStore` and tests call it;
// a row without a stable ID cannot be addressed by a mutation, so it is left out of the cart.

extension CartItem {
    init?(_ product: ProductEntity) {
        guard let id = product.id else { return nil }
        self.init(
            id: id,
            displayName: product.displayName,
            category: product.categoryValue,
            isPurchased: product.isPurchasedValue,
            createdByName: product.createdByName,
            purchasedByName: product.purchasedByName
        )
    }
}

extension CartList {
    init?(_ list: ShoppingListEntity) {
        guard let id = list.id else { return nil }
        self.init(id: id, hasStore: list.store != nil, createdAt: list.createdAt)
    }
}

extension HistoryLine {
    /// Deduplicated History lines in archive order (`HistoryItems.unique`). An item without an ID
    /// still shows; it gets a fresh row identity because nothing addresses it.
    static func lines(from entries: [PurchaseHistoryEntity]) -> [HistoryLine] {
        HistoryItems.unique(from: entries).map { item in
            HistoryLine(
                id: item.id ?? UUID(),
                displayName: item.displayName,
                category: item.categoryValue,
                purchaseMoment: item.purchaseMoment,
                createdByName: item.createdByName,
                purchasedByName: item.purchasedByName
            )
        }
    }
}
