import Foundation

/// Paged, read-only purchase history (REQ-SHELL-020) as value snapshots.
@MainActor
protocol HistoryBrowsing: AnyObject {
    /// The loaded pages' lines, deduplicated across peer replicas (REQ-HIST-040).
    var historyLines: [HistoryLine] { get }
    var historyHasMore: Bool { get }
    func loadMoreHistory()
}
