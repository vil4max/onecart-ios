@testable import OneCart
import Testing

@Suite("CartCelebrationTests")
struct CartCelebrationTests {
    struct Item {
        let isPurchased: Bool
    }

    @Test("Empty cart is not all purchased")
    func emptyCartIsNotAllPurchased() {
        let items: [Item] = []
        let isAllDone = !items.isEmpty && items.allSatisfy(\.isPurchased)
        #expect(!isAllDone)
    }

    @Test("Partial cart is not all purchased")
    func partialCartIsNotAllPurchased() {
        let items = [
            Item(isPurchased: true),
            Item(isPurchased: false),
            Item(isPurchased: true),
        ]
        let isAllDone = !items.isEmpty && items.allSatisfy(\.isPurchased)
        #expect(!isAllDone)
    }

    @Test("Cart with all items checked is all purchased")
    func fullCartIsAllPurchased() {
        let items = [
            Item(isPurchased: true),
            Item(isPurchased: true),
        ]
        let isAllDone = !items.isEmpty && items.allSatisfy(\.isPurchased)
        #expect(isAllDone)
    }

    @Test("Will complete cart triggers only on last remaining to-buy item")
    func willCompleteCartTrigger() {
        let toBuyCount = 1
        let isPurchased = false
        let willComplete = !isPurchased && toBuyCount == 1
        #expect(willComplete)

        let multipleToBuyCount = 2
        let willNotComplete = !isPurchased && multipleToBuyCount == 1
        #expect(!willNotComplete)
    }

    @Test("Celebration triggers only once per completion and does not repeat on uncheck/recheck")
    func celebrationTriggersOncePerCompletion() {
        var hasCelebrated = false
        var celebrationCount = 0

        func toggleItem(isCurrentlyPurchased: Bool, toBuyCount: Int) {
            let willComplete = !isCurrentlyPurchased && toBuyCount == 1
            if willComplete, !hasCelebrated {
                hasCelebrated = true
                celebrationCount += 1
            }
        }

        // 1. Initial cart completion: last item toggled
        toggleItem(isCurrentlyPurchased: false, toBuyCount: 1)
        #expect(hasCelebrated)
        #expect(celebrationCount == 1)

        // 2. User unchecks an item (toBuyCount becomes 1 again)
        // User re-checks the item
        toggleItem(isCurrentlyPurchased: false, toBuyCount: 1)
        #expect(celebrationCount == 1, "Should NOT trigger celebration again on uncheck/recheck")

        // 3. User adds a new product -> resets celebration gating
        hasCelebrated = false

        // 4. Completing the new product triggers celebration again
        toggleItem(isCurrentlyPurchased: false, toBuyCount: 1)
        #expect(celebrationCount == 2)
    }
}
