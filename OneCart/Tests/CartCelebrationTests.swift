@testable import OneCart
import Testing

@Suite("CartCelebrationTests")
struct CartCelebrationTests {
    @Test("Empty cart is not all purchased")
    func emptyCartIsNotAllPurchased() {
        #expect(!CartCelebration.isAllPurchased(totalCount: 0, toBuyCount: 0))
    }

    @Test("Partial cart is not all purchased")
    func partialCartIsNotAllPurchased() {
        #expect(!CartCelebration.isAllPurchased(totalCount: 3, toBuyCount: 1))
    }

    @Test("Cart with all items checked is all purchased")
    func fullCartIsAllPurchased() {
        #expect(CartCelebration.isAllPurchased(totalCount: 2, toBuyCount: 0))
    }

    @Test("Checking the last to-buy item completes the cart")
    func checkingLastItemCompletesCart() {
        #expect(CartCelebration.willCompleteCart(togglingPurchasedItem: false, toBuyCount: 1))
    }

    @Test("Checking an item while others remain does not complete the cart")
    func checkingWithOthersRemainingDoesNotComplete() {
        #expect(!CartCelebration.willCompleteCart(togglingPurchasedItem: false, toBuyCount: 2))
    }

    @Test("Unchecking a purchased item never completes the cart")
    func uncheckingNeverCompletesCart() {
        #expect(!CartCelebration.willCompleteCart(togglingPurchasedItem: true, toBuyCount: 1))
        #expect(!CartCelebration.willCompleteCart(togglingPurchasedItem: true, toBuyCount: 0))
    }
}
