import Foundation
@testable import OneCart
import SwiftUI
import Testing

/// History hosted over `FakeHistoryBrowser` value snapshots: day order, the overnight caption,
/// paging and the absence of any clearing control (REQ-SHELL-020, REQ-HIST-050, REQ-HIST-030).
@MainActor
@Suite("HostedHistoryViewTests")
struct HostedHistoryViewTests {
    private static let calendar = Calendar(identifier: .gregorian)

    /// Words a clearing or deleting control would carry in any of the app's languages.
    private static let clearingWords = ["delete", "clear", "remove", "удал", "очист", "видал"]

    /// Bread bought by Alex yesterday and Milk two days ago.
    private static func twoDayHistory() throws -> (lines: [HistoryLine], yesterday: Date, older: Date) {
        let startOfToday = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))
        let older = try #require(calendar.date(byAdding: .day, value: -2, to: startOfToday))
        let lines: [HistoryLine] = [
            .bought("Bread", at: yesterday.addingTimeInterval(3600)),
            .bought("Milk", at: older.addingTimeInterval(3600)),
        ]
        return (lines, yesterday, older)
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
        let (lines, _, _) = try Self.twoDayHistory()
        let browser = FakeHistoryBrowser()
        browser.historyLines = lines
        let viewModel = HistoryViewModel(history: browser, calendar: Self.calendar)
        let hosted = HostedView(HistoryView(viewModel: viewModel))
        defer { hosted.tearDown() }

        let rows = hosted.elements(identifier: "history.day_row")
        #expect(rows.count == 2)
        #expect(rows.first?.label?.contains(String(localized: "history.day_yesterday")) == true)
        #expect(rows.first?.label?.contains("Bread") == true)
        #expect(rows.last?.label?.contains(String(localized: "history.day_yesterday")) == false)
        #expect(rows.last?.label?.contains("Milk") == true)

        #expect(
            hosted.element(identifier: "history.overnight_caption")?
                .label == String(localized: "history.how_it_works"))

        // REQ-HIST-050: the only buttons are the day rows; no label reads as a deletion.
        #expect(hosted.buttons.allSatisfy { $0.identifier == "history.day_row" })
        for word in Self.clearingWords {
            #expect(!hosted.containsText(word), "a control mentioning \(word) is on the History screen")
        }
    }

    @Test("REQ-HIST-030: show more appears once the session has more and forwards the request")
    func showMoreAppearsAndForwards() async throws {
        let (lines, _, _) = try Self.twoDayHistory()
        let browser = FakeHistoryBrowser()
        browser.historyLines = lines
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
        let (lines, yesterday, _) = try Self.twoDayHistory()
        let browser = FakeHistoryBrowser()
        browser.historyLines = lines
        let viewModel = HistoryViewModel(history: browser, calendar: Self.calendar)
        let day = try #require(viewModel.dayGroups.first { Self.calendar.isDate($0.dayStart, inSameDayAs: yesterday) })
        let hosted = HostedView(NavigationStack { HistoryDayDetailView(viewModel: viewModel, group: day) })
        defer { hosted.tearDown() }

        let rows = hosted.elements(identifier: "history.item_row")
        #expect(rows.count == 1)
        #expect(rows.first?.label?.hasPrefix("Bread") == true)
        #expect(rows.first?.label?.contains(String(localized: "history.bought_by \("Alex")")) == true)
        #expect(hosted.containsLabel(String(localized: "common.category.bakery")))
        #expect(
            hosted.element(identifier: "history.read_only_footer")?
                .label == String(localized: "history.read_only_footer"))
        #expect(hosted.buttons.isEmpty)
        #expect(hosted.uiLabelTexts.contains(String(localized: "history.day_yesterday")))
        for word in Self.clearingWords {
            #expect(!hosted.containsText(word), "a control mentioning \(word) is on the day detail")
        }
    }

    @Test("REQ-SYNC-020: an archived item names who added it next to who bought it; no name, no caption")
    func dayDetailShowsWhoAdded() async throws {
        let moment = Date()
        let browser = FakeHistoryBrowser()
        browser.historyLines = [
            .bought("Bread", at: moment, createdByName: "Maria"),
            // A blank name synced from another device must read as no name, not as "Added by ".
            .bought("Milk", at: moment, createdByName: "   "),
        ]
        let viewModel = HistoryViewModel(history: browser, calendar: Self.calendar)
        let day = try #require(viewModel.dayGroups.first)
        let hosted = HostedView(NavigationStack { HistoryDayDetailView(viewModel: viewModel, group: day) })
        defer { hosted.tearDown() }

        let rows = hosted.elements(identifier: "history.item_row")
        #expect(rows.count == 2)
        let addedBy = String(localized: "history.added_by \("Maria")")
        let boughtBy = String(localized: "history.bought_by \("Alex")")
        let bread = try #require(rows.first { $0.label?.hasPrefix("Bread") == true })
        #expect(bread.label?.contains(addedBy) == true)
        #expect(bread.label?.contains(boughtBy) == true)
        let milk = try #require(rows.first { $0.label?.hasPrefix("Milk") == true })
        #expect(
            milk.label?
                .contains(String(localized: "history.added_by \("")").trimmingCharacters(in: .whitespaces)) == false)
        #expect(milk.label?.contains(boughtBy) == true)
    }
}
