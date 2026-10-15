import Foundation

// Entity → value mapping for the screens' snapshots. Only `CartContentStore` and tests call it;
// a row without a stable ID cannot be addressed by a mutation, so it is left out of the cart
// (`CartContentStore.rebuildDerivedCollections` drops such rows for every surface).

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
    /// still shows, keyed by its record.
    static func lines(from entries: [PurchaseHistoryEntity]) -> [HistoryLine] {
        HistoryItems.unique(from: entries).map { item in
            HistoryLine(
                id: lineID(for: item),
                displayName: item.displayName,
                category: item.categoryValue,
                purchaseMoment: item.purchaseMoment,
                createdByName: item.createdByName,
                purchasedByName: item.purchasedByName
            )
        }
    }

    /// The same family fallback as `HistoryItems.unique`, so a row's identity is the identity
    /// History deduplicates by.
    static func lineID(for item: HistoryItemEntity) -> Identity {
        guard let familyID = item.familySpace?.id ?? item.history?.familySpace?.id,
            let productID = item.id
        else { return .record(item.objectID.uriRepresentation()) }
        return .purchase(familyID: familyID, productID: productID)
    }
}
