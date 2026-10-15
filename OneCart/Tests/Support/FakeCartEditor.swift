import Foundation
@testable import OneCart

@MainActor
final class FakeCartEditor: CartEditing {
    struct AddedProduct: Equatable {
        let listID: UUID?
        let draft: ProductDraft
    }

    struct UpdatedProduct {
        let product: ProductEntity
        let draft: ProductDraft
    }

    var addedProducts: [AddedProduct] = []
    /// Answer for every add; `nil` rejects it, an existing line's ID reports a duplicate.
    var addResult: UUID?
    var updatedProducts: [UpdatedProduct] = []
    var toggledProducts: [ProductEntity] = []
    var requestedPurchaseStates: [Bool] = []
    var deletedProducts: [ProductEntity] = []
    var syncReasons: [CartSyncReason] = []

    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async -> UUID? {
        addedProducts.append(AddedProduct(listID: list.id, draft: draft))
        return addResult
    }

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        updatedProducts.append(UpdatedProduct(product: product, draft: draft))
    }

    func setPurchased(_ product: ProductEntity, isPurchased: Bool) async {
        toggledProducts.append(product)
        requestedPurchaseStates.append(isPurchased)
    }

    func deleteProduct(_ product: ProductEntity) async {
        deletedProducts.append(product)
    }

    func syncCart(reason: CartSyncReason) async {
        syncReasons.append(reason)
    }
}
