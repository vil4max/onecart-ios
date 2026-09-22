import Foundation

/// Mutations of the living cart plus the explicit sync the cart screen triggers.
@MainActor
protocol CartEditing: AnyObject {
    /// Returns the ID of the affected line: a new one, or the existing line when the
    /// name already lives on the cart (REQ-CART-090). `nil` means the add was rejected.
    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async -> UUID?
    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async
    func togglePurchased(_ product: ProductEntity) async
    func deleteProduct(_ product: ProductEntity) async
    func syncCart(reason: CartSyncReason) async
}
