import Foundation

// Immutable snapshots of the cart and History that the screens read through the role
// protocols. `CartContentStore` maps the Core Data entities into them once per reload, so a
// view never holds a managed object that a hard refresh can reset under it; mutations go back
// by ID and the session resolves the row on its own context.

/// One line of the living cart as the screen draws it.
struct CartItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let category: ProductCategory
    let isPurchased: Bool
    let createdByName: String?
    let purchasedByName: String?
}

/// An active shopping list; the cart shows only the primary one (`primary(in:)`).
struct CartList: Identifiable, Hashable, Sendable {
    let id: UUID
    /// True for a list tied to a store; the general list has none.
    let hasStore: Bool
    let createdAt: Date?

    static func primary(in lists: [CartList]) -> CartList? {
        PrimaryListRule.pick(from: lists, hasStore: \.hasStore, createdAt: \.createdAt)
    }
}

/// One archived purchase as History shows it, already deduplicated across peer replicas.
struct HistoryLine: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let category: ProductCategory
    /// The moment the line counts as bought; History groups lines by its day.
    let purchaseMoment: Date
    let createdByName: String?
    let purchasedByName: String?
}

/// The one list the cart shows among the active lists: the general (no-store) list, else the
/// oldest. The cart screen, Siri, the widgets and the shopping trip all pick through this rule,
/// for entities and for values alike, so a line checked or added on one surface is the line
/// the others show.
enum PrimaryListRule {
    static func pick<List>(
        from lists: [List],
        hasStore: (List) -> Bool,
        createdAt: (List) -> Date?
    ) -> List? {
        if let general = lists.first(where: { !hasStore($0) }) {
            return general
        }
        return lists.min { lhs, rhs in
            (createdAt(lhs) ?? .distantFuture) < (createdAt(rhs) ?? .distantFuture)
        }
    }
}
