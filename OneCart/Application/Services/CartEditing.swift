import Foundation

/// Mutations of the living cart plus the explicit sync the cart screen triggers. Lines and lists
/// are addressed by ID; the session resolves them on its own context, and a line that is gone by
/// then (a hard refresh reset, another shopper's delete) is dropped without an alert.
@MainActor
protocol CartEditing: AnyObject {
    /// Returns the ID of the affected line: a new one, or the existing line when the
    /// name already lives on the cart (REQ-CART-090). `nil` means the add was rejected.
    func addProduct(toListID listID: UUID, draft: ProductDraft) async -> UUID?
    func updateProduct(id: UUID, draft: ProductDraft) async
    /// `isPurchased` is the state the user asked for from the row they saw, so a check another
    /// shopper already made is kept rather than flipped back.
    func setPurchased(productID: UUID, isPurchased: Bool) async
    func deleteProduct(id: UUID) async
    func syncCart(reason: CartSyncReason) async
}
