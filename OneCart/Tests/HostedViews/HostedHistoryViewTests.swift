import CoreData
import Foundation
@testable import OneCart
import SwiftUI
import Testing

/// History hosted over `FakeHistoryBrowser`: day order, the overnight caption, paging and the
/// absence of any clearing control (REQ-SHELL-020, REQ-HIST-050, REQ-HIST-030).
@MainActor
@Suite("HostedHistoryViewTests")
struct HostedHistoryViewTests {
    private static let calendar = Calendar(identifier: .gregorian)

    /// Words a clearing or deleting control would carry in any of the app's languages.
    private static let clearingWords = ["delete", "clear", "remove", "удал", "очист", "видал"]

    /// Bread bought yesterday and Milk two days ago, archived through the repository.
    private static func twoDayHistory() async throws -> (fixture: CartFixture, yesterday: Date, older: Date) {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread", purchased: true)
        let milkID = try await fixture.addProduct(named: "Milk", purchased: true)
        let startOfToday = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))
        let older = try #require(calendar.date(byAdding: .day, value: -2, to: startOfToday))
        try await fixture.persistence.performBackgroundTask { context in
            let request = ProductEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", [breadID, milkID].map { $0 as NSUUID })
            for product in try context.fetch(request) {
                product.purchasedAt = product.id == breadID ? yesterday : older
            }
        }
        _ = try await fixture.repository.completePurchased(listID: fixture.listID)
        await fixture.settle()
        return (fixture, yesterday, older)
    }

    @Test("REQ-SHELL-020: an empty History explains itself and offers no control")
    func emptyStateHasNoControls() {
        let browser = FakeHistoryBrowser()
        let hosted = HostedView(HistoryView(viewModel: HistoryViewModel(history: browser)))
        defer { hosted.tearDown() }

        #expect(hosted.containsLabel(String(localized: "history.empty_headline")))
        #expect(hosted.containsLabel(String(localized: "history.empty_message")))
        #expect(hosted.buttons.isEmpty)
        #expect(hosted.uiLabelTexts.contains(String(localized: "history.nav_title")))
    }

    @Test("REQ-SHELL-020: days list newest first with the overnight caption, and nothing on the screen deletes")
    func daysNewestFirstReadOnlyWithCaption() async throws {
        let (fixture, _, _) = try await Self.twoDayHistory()
        let browser = FakeHistoryBrowser()
        browser.history = try fixture.history
        let viewModel = HistoryViewModel(history: browser, calendar: Self.calendar)
        let hosted = HostedView(HistoryView(viewModel: viewModel))
        defer { hosted.tearDown() }

        let rows = hosted.elements(identifier: "history.day_row")
        #expect(rows.count == 2)
        #expect(rows.first?.label?.contains(String(localized: "history.day_yesterday")) == true)
        #expect(rows.first?.label?.contains("Bread") == true)
        #expect(rows.last?.label?.contains(String(localized: "history.day_yesterday")) == false)
        #expect(rows.last?.label?.contains("Milk") == true)

        #expect(hosted.element(identifier: "history.overnight_caption")?
            .label == String(localized: "history.how_it_works"))

        // REQ-HIST-050: the only buttons are the day rows; no label reads as a deletion.
        #expect(hosted.buttons.allSatisfy { $0.identifier == "history.day_row" })
        for word in Self.clearingWords {
            #expect(!hosted.containsText(word), "a control mentioning \(word) is on the History screen")
        }
    }

    @Test("REQ-HIST-030: show more appears once the session has more and forwards the request")
    func showMoreAppearsAndForwards() async throws {
        let (fixture, _, _) = try await Self.twoDayHistory()
        let browser = FakeHistoryBrowser()
        browser.history = try fixture.history
        let viewModel = HistoryViewModel(history: browser, calendar: Self.calendar)
        let hosted = HostedView(HistoryView(viewModel: viewModel))
        defer { hosted.tearDown() }
        #expect(hosted.element(identifier: "history.show_more") == nil)

        browser.historyHasMore = true
        #expect(await hosted.pump { hosted.element(identifier: "history.show_more") != nil })

        let showMore = try #require(hosted.element(identifier: "history.show_more"))
        #expect(showMore.label == String(localized: "history.show_more"))
        #expect(showMore.activate())
        #expect(await hosted.pump { browser.loadMoreCount == 1 })
    }

    @Test("REQ-HIST-050: an opened day lists its items read-only with the archive footer")
    func dayDetailIsReadOnly() async throws {
        let (fixture, yesterday, _) = try await Self.twoDayHistory()
        let browser = FakeHistoryBrowser()
        browser.history = try fixture.history
        let viewModel = HistoryViewModel(history: browser, calendar: Self.calendar)
        let day = try #require(viewModel.dayGroups.first { Self.calendar.isDate($0.dayStart, inSameDayAs: yesterday) })
        let hosted = HostedView(NavigationStack { HistoryDayDetailView(viewModel: viewModel, group: day) })
        defer { hosted.tearDown() }

        let rows = hosted.elements(identifier: "history.item_row")
        #expect(rows.count == 1)
        #expect(rows.first?.label?.hasPrefix("Bread") == true)
        #expect(rows.first?.label?.contains(String(localized: "history.bought_by \("Alex")")) == true)
        #expect(hosted.containsLabel(String(localized: "common.category.bakery")))
        #expect(hosted.element(identifier: "history.read_only_footer")?
            .label == String(localized: "history.read_only_footer"))
        #expect(hosted.buttons.isEmpty)
        #expect(hosted.uiLabelTexts.contains(String(localized: "history.day_yesterday")))
        for word in Self.clearingWords {
            #expect(!hosted.containsText(word), "a control mentioning \(word) is on the day detail")
        }
    }
}
