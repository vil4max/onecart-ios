import Foundation

/// The primary list's lines as the cart screen draws them, derived once from the session's
/// snapshot instead of re-filtering it on every property read. `items` keeps the session's
/// order (REQ-SHELL-010: newest to-buy first, then completed); both halves keep it too.
struct CartLines {
    typealias Section = (category: ProductCategory, items: [CartItem])

    let items: [CartItem]
    let toBuy: [CartItem]
    let completed: [CartItem]
    /// To-buy lines grouped by category in `ProductCategory` order, each in cart order.
    let toBuySections: [Section]

    static let empty = CartLines(items: [])

    init(items: [CartItem]) {
        self.items = items
        toBuy = items.filter { !$0.isPurchased }
        completed = items.filter(\.isPurchased)
        toBuySections = ProductCategory.groupedSections(from: toBuy) { $0.category }
    }

    var totalCount: Int {
        items.count
    }

    var purchasedCount: Int {
        completed.count
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    var isAllPurchased: Bool {
        CartCelebration.isAllPurchased(totalCount: totalCount, toBuyCount: toBuy.count)
    }

    /// Completed share of the cart for the progress bar; an empty cart reads as no progress.
    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(purchasedCount) / Double(totalCount)
    }
}
