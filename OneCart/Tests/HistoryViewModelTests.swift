import Foundation
@testable import OneCart
import Testing

/// The History ViewModel over value fakes: no Core Data store is involved.
@MainActor
@Suite("HistoryViewModelTests")
struct HistoryViewModelTests {
    @Test("REQ-SHELL-020: days are newest first and an opened day resolves to its live contents")
    func daysNewestFirstWithLiveDetail() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: startOfToday))

        let browser = FakeHistoryBrowser()
        browser.historyLines = [
            .bought("Milk", at: twoDaysAgo.addingTimeInterval(3600)),
            .bought("Bread", at: yesterday.addingTimeInterval(7200)),
        ]
        let viewModel = HistoryViewModel(history: browser, calendar: calendar)

        let groups = viewModel.dayGroups
        #expect(!viewModel.isEmpty)
        #expect(groups.map(\.dayStart) == [yesterday, twoDaysAgo])
        #expect(groups[0].items.map(\.displayName) == ["Bread"])
        #expect(groups[1].items.map(\.displayName) == ["Milk"])

        let snapshot = HistoryDayGroup(dayStart: twoDaysAgo, items: [])
        #expect(viewModel.liveGroup(for: snapshot).items.map(\.displayName) == ["Milk"])

        let missingDay = HistoryDayGroup(dayStart: startOfToday, items: [])
        #expect(viewModel.liveGroup(for: missingDay).dayStart == startOfToday)
        #expect(viewModel.liveGroup(for: missingDay).items.isEmpty)
    }

    @Test("REQ-SHELL-020: an opened day sections its items by category in cart order and previews the names")
    func daySectionsByCategoryAndPreviewsNames() async throws {
        let moment = Date()
        let browser = FakeHistoryBrowser()
        browser.historyLines = ["Coffee", "Bread", "Apple", "Milk"].map { HistoryLine.bought($0, at: moment) }
        let viewModel = HistoryViewModel(history: browser, calendar: Calendar(identifier: .gregorian))

        let day = try #require(viewModel.dayGroups.first)
        #expect(day.namesPreview == "Apple, Bread, Coffee, Milk")

        let sections = day.categorySections
        #expect(sections.map(\.category) == [.dairyEggs, .produce, .bakery, .hotDrinks])
        #expect(sections.map { $0.items.map(\.displayName) } == [["Milk"], ["Apple"], ["Bread"], ["Coffee"]])

        let emptyDay = HistoryDayGroup(dayStart: day.dayStart, items: [])
        #expect(emptyDay.categorySections.isEmpty)
        #expect(emptyDay.namesPreview.isEmpty)
    }

    @Test("REQ-HIST-030: show more is offered only while the session has more and forwards the request")
    func showMoreMirrorsSessionAndForwards() {
        let browser = FakeHistoryBrowser()
        let viewModel = HistoryViewModel(history: browser)

        #expect(viewModel.isEmpty)
        #expect(viewModel.dayGroups.isEmpty)
        #expect(!viewModel.hasMore)

        browser.historyHasMore = true
        #expect(viewModel.hasMore)

        viewModel.loadMore()
        #expect(browser.loadMoreCount == 1)
    }
}
