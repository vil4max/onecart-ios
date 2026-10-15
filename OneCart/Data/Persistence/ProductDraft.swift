import Foundation

/// What an add or a rename writes to a cart line (REQ-CART-020, REQ-CART-060): the name and the
/// category it is grouped under. The legacy quantity, unit, price, note, URL and catalog
/// attributes stay in the model for CloudKit and older clients, but the app no longer writes
/// them, so values an older build stored are left as they are.
struct ProductDraft: Equatable {
    var name: String
    var category: ProductCategory
}
