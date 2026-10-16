import Foundation

/// Cart mutations live in `CartMutationService`; the session forwards the role protocol
/// (`CartEditing`) and the entity-based calls the application layer and the demo make.
extension AppSession {
    @discardableResult
    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async -> UUID? {
        guard let listID = list.id else { return nil }
        return await addProduct(toListID: listID, draft: draft)
    }

    @discardableResult
    func addProduct(toListID listID: UUID, draft: ProductDraft) async -> UUID? {
        await cartMutations.addProduct(toListID: listID, draft: draft)
    }

    func updateProduct(id: UUID, draft: ProductDraft) async {
        await cartMutations.updateProduct(id: id, draft: draft)
    }

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        await cartMutations.updateProduct(product, draft: draft)
    }

    /// Flips the row as the caller holds it; for callers without a rendered row state.
    func togglePurchased(_ product: ProductEntity) async {
        await setPurchased(product, isPurchased: !product.isPurchasedValue)
    }

    func setPurchased(productID: UUID, isPurchased: Bool) async {
        await cartMutations.setPurchased(productID: productID, isPurchased: isPurchased)
    }

    func setPurchased(_ product: ProductEntity, isPurchased: Bool) async {
        await cartMutations.setPurchased(product, isPurchased: isPurchased)
    }

    func deleteProduct(id: UUID) async {
        await cartMutations.deleteProduct(id: id)
    }

    func deleteProduct(_ product: ProductEntity) async {
        await cartMutations.deleteProduct(product)
    }

    func completePurchasedItems(_ list: ShoppingListEntity) async {
        await cartMutations.completePurchasedItems(list)
    }

    func archiveStalePurchasedIfNeeded(calendar: Calendar = .current) async {
        await cartMutations.archiveStalePurchasedIfNeeded(calendar: calendar)
    }

    func deduplicateCartIfNeeded() async {
        await cartMutations.deduplicateCartIfNeeded()
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        cartContent.products(inListID: listID)
    }

    func syncCart(reason: CartSyncReason) async {
        await applyCloudSyncResult(await cloudSync.syncCart(reason: reason))
        switch reason {
        case .appear, .foreground, .cloudImport:
            // CloudKit may have delivered a same-name row from another device
            // with a different stable ID — merge before archiving/presenting.
            await deduplicateCartIfNeeded()
        case .pull:
            break
        }
        switch reason {
        case .appear, .foreground:
            await archiveStalePurchasedIfNeeded()
        case .pull, .cloudImport:
            break
        }
    }

    func loadMoreHistory() {
        guard let familySpaceID = activeFamilySpace?.id else { return }
        do {
            try cartContent.loadMoreHistory(familySpaceID: familySpaceID)
        } catch {
            show(error)
        }
    }
}
