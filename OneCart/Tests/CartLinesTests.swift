import Foundation
@testable import OneCart
import Testing

@MainActor
@Suite("CartLinesTests")
struct CartLinesTests {
    /// Cart order as the session hands it over: newest to-buy first, then completed.
    private static let cartOrder: [CartItem] = [
        .line("Apples"),
        .line("Milk"),
        .line("Cheese"),
        .line("Bread", purchased: true),
        .line("Coffee", purchased: true),
    ]

    @Test("REQ-SHELL-010: to-buy lines group by category in category order and keep cart order inside a section")
    func toBuySectionsFollowCategoryOrder() {
        let lines = CartLines(items: Self.cartOrder)

        let categories = lines.toBuySections.map(\.category)
        let expectedOrder = ProductCategory.allCases.filter { Set(categories).contains($0) }
        #expect(categories == expectedOrder)
        #expect(lines.toBuySections.flatMap(\.items).count == 3)
        for section in lines.toBuySections {
            let inCartOrder = lines.toBuy.filter { $0.category == section.category }
            #expect(section.items.map(\.id) == inCartOrder.map(\.id))
        }
        #expect(lines.toBuy.map(\.displayName) == ["Apples", "Milk", "Cheese"])
    }

    @Test("REQ-SHELL-010: completed lines keep cart order after the to-buy lines")
    func completedKeepsCartOrder() {
        let lines = CartLines(items: Self.cartOrder)

        #expect(lines.completed.map(\.displayName) == ["Bread", "Coffee"])
        #expect(lines.items.map(\.id) == Self.cartOrder.map(\.id))
    }

    @Test("REQ-SHELL-010: counts, all-purchased and progress follow the completed lines")
    func countsAndProgress() {
        let partial = CartLines(items: Self.cartOrder)
        #expect(partial.totalCount == 5)
        #expect(partial.purchasedCount == 2)
        #expect(!partial.isEmpty)
        #expect(!partial.isAllPurchased)
        #expect(partial.progressFraction == 0.4)

        let done = CartLines(items: [.line("Bread", purchased: true)])
        #expect(done.isAllPurchased)
        #expect(done.progressFraction == 1)
        #expect(done.toBuySections.isEmpty)
    }

    @Test("REQ-SHELL-010: an empty cart reads as no progress and not all purchased")
    func emptyCart() {
        let lines = CartLines.empty
        #expect(lines.isEmpty)
        #expect(lines.totalCount == 0)
        #expect(lines.progressFraction == 0)
        #expect(!lines.isAllPurchased)
    }

    @Test("REQ-SHELL-010: the screen model rebuilds its lines when the session replaces the snapshot")
    func viewModelFollowsReplacedSnapshot() throws {
        let harness = try CartHarness(lines: [.line("Milk")])
        #expect(harness.viewModel.totalCount == 1)
        #expect(harness.viewModel.purchasedCount == 0)

        harness.show([.line("Milk", purchased: true), .line("Bread", purchased: true)])
        #expect(harness.viewModel.totalCount == 2)
        #expect(harness.viewModel.isAllPurchased)
        #expect(harness.viewModel.toBuySections.isEmpty)
    }

    @Test("REQ-SHELL-010: a cart whose primary list has no ID reads as unavailable, not empty")
    func unaddressablePrimaryListIsUnavailable() throws {
        let harness = try CartHarness()
        #expect(!harness.viewModel.isPrimaryListUnavailable)

        harness.state.hasActiveCartLists = true
        #expect(harness.viewModel.isPrimaryListUnavailable)
        #expect(harness.viewModel.isEmpty)
    }
}
