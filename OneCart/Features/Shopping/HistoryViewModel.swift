import Foundation

/// History by day: newest first, paged, read-only (REQ-SHELL-020).
@MainActor
@Observable
final class HistoryViewModel {
    private let history: any HistoryBrowsing
    private let calendar: Calendar

    init(history: any HistoryBrowsing, calendar: Calendar = .current) {
        self.history = history
        self.calendar = calendar
    }

    /// Grouping dedupes and sorts the whole history; callers read it once per body pass.
    var dayGroups: [HistoryDayGroup] {
        HistoryDayGroup.groups(from: history.history, calendar: calendar)
    }

    var isEmpty: Bool {
        history.history.isEmpty
    }

    var hasMore: Bool {
        history.historyHasMore
    }

    func loadMore() {
        history.loadMoreHistory()
    }

    /// The current contents of an opened day; the snapshot the row was tapped with is the
    /// fallback when that day is no longer in the loaded page.
    func liveGroup(for group: HistoryDayGroup) -> HistoryDayGroup {
        dayGroups.first { calendar.isDate($0.dayStart, inSameDayAs: group.dayStart) } ?? group
    }
}
