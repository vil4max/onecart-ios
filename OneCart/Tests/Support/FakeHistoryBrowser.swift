import Foundation
@testable import OneCart

@MainActor
@Observable
final class FakeHistoryBrowser: HistoryBrowsing {
    var history: [PurchaseHistoryEntity] = []
    var historyHasMore = false
    var loadMoreCount = 0

    func loadMoreHistory() {
        loadMoreCount += 1
    }
}
