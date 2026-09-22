import Foundation

/// Paged, read-only purchase history (REQ-SHELL-020).
@MainActor
protocol HistoryBrowsing: AnyObject {
    var history: [PurchaseHistoryEntity] { get }
    var historyHasMore: Bool { get }
    func loadMoreHistory()
}
