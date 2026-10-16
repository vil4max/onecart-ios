import Foundation

/// SF Symbol names the cart screen, the widgets and the shopping trip share, so one state draws
/// the same glyph on every surface.
enum CartSymbolName {
    /// The check control of a cart line.
    static func purchase(isPurchased: Bool) -> String {
        isPurchased ? "checkmark.circle.fill" : "circle"
    }

    /// The glyph ahead of the "N of M completed" progress line.
    static func progress(isAllPurchased: Bool) -> String {
        isAllPurchased ? "checkmark.seal.fill" : "cart"
    }
}
