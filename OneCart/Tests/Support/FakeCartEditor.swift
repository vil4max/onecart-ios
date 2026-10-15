import Foundation
@testable import OneCart

@MainActor
final class FakeCartEditor: CartEditing {
    struct AddedProduct: Equatable {
        let listID: UUID
        let draft: ProductDraft
    }

    struct UpdatedProduct: Equatable {
        let id: UUID
        let draft: ProductDraft
    }

    var addedProducts: [AddedProduct] = []
    /// Answer for every add; `nil` rejects it, an existing line's ID reports a duplicate.
    var addResult: UUID?
    var updatedProducts: [UpdatedProduct] = []
    var toggledProductIDs: [UUID] = []
    var requestedPurchaseStates: [Bool] = []
    var deletedProductIDs: [UUID] = []
    var syncReasons: [CartSyncReason] = []

    func addProduct(toListID listID: UUID, draft: ProductDraft) async -> UUID? {
        addedProducts.append(AddedProduct(listID: listID, draft: draft))
        return addResult
    }

    func updateProduct(id: UUID, draft: ProductDraft) async {
        updatedProducts.append(UpdatedProduct(id: id, draft: draft))
    }

    func setPurchased(productID: UUID, isPurchased: Bool) async {
        toggledProductIDs.append(productID)
        requestedPurchaseStates.append(isPurchased)
    }

    func deleteProduct(id: UUID) async {
        deletedProductIDs.append(id)
    }

    func syncCart(reason: CartSyncReason) async {
        syncReasons.append(reason)
    }
}
