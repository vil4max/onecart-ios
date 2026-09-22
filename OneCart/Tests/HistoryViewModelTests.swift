import CoreData
import Foundation
@testable import OneCart
import Testing

@MainActor
@Suite("HistoryViewModelTests")
struct HistoryViewModelTests {
    @Test("REQ-SHELL-020: days are newest first and an opened day resolves to its live contents")
    func daysNewestFirstWithLiveDetail() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread", purchased: true)
        let milkID = try await fixture.addProduct(named: "Milk", purchased: true)
        let calendar = Calendar(identifier: .gregorian)
        let startOfToday = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: startOfToday))
        try await fixture.persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", [breadID, milkID].map { $0 as NSUUID })
            for product in try context.fetch(request) {
                product.purchasedAt = product.id == breadID ? yesterday : twoDaysAgo
            }
        }
        _ = try await fixture.repository.completePurchased(listID: fixture.listID)
        await fixture.settle()

        let browser = FakeHistoryBrowser()
        browser.history = try fixture.history
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
        let fixture = try await CartFixture.make()
        for name in ["Coffee", "Bread", "Apple", "Milk"] {
            _ = try await fixture.addProduct(named: name, purchased: true)
        }
        _ = try await fixture.repository.completePurchased(listID: fixture.listID)
        await fixture.settle()

        let browser = FakeHistoryBrowser()
        browser.history = try fixture.history
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
