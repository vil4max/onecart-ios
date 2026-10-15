import Foundation
@testable import OneCart
import Testing

/// The intents reach the app only through the `CartIntentHandling` dependency; here a fake
/// stands in for the session `OneCartApp` registers with `AppDependencyManager`.
@Suite("Intent dependency")
@MainActor
struct CartIntentInjectionTests {
    @Test("REQ-WIDGET-020: a purchase toggle with a malformed ID throws invalidRequest and forwards nothing")
    func malformedToggleForwardsNothing() async {
        let cart = FakeCartIntentHandler()
        let valid = UUID().uuidString
        let intents = [
            ToggleProductPurchasedIntent(productID: "not-a-uuid", accountID: valid, familyID: valid, isPurchased: true),
            ToggleProductPurchasedIntent(productID: valid, accountID: "", familyID: valid, isPurchased: true),
            ToggleProductPurchasedIntent(productID: valid, accountID: valid, familyID: "family", isPurchased: false),
        ]

        for intent in intents {
            await #expect(throws: WidgetPurchaseError.invalidRequest) {
                try await intent.perform(using: cart)
            }
        }
        #expect(cart.purchases.isEmpty)
    }

    @Test("REQ-WIDGET-020: a valid purchase toggle forwards exactly one request with its IDs and state")
    func validToggleForwardsOneRequest() async throws {
        let cart = FakeCartIntentHandler()
        let productID = UUID()
        let accountID = UUID()
        let familyID = UUID()
        let intent = ToggleProductPurchasedIntent(
            productID: productID.uuidString,
            accountID: accountID.uuidString,
            familyID: familyID.uuidString,
            isPurchased: true
        )

        try await intent.perform(using: cart)

        #expect(cart.purchases.count == 1)
        let request = try #require(cart.purchases.first)
        #expect(request.productID == productID)
        #expect(request.accountID == accountID)
        #expect(request.familyID == familyID)
        #expect(request.isPurchased)
        #expect(request.id.uuidString == intent.requestID)
    }

    @Test("REQ-SIRI-010: the add intent forwards the spoken names unchanged")
    func addIntentForwardsTheNames() async throws {
        let cart = FakeCartIntentHandler()
        cart.addResult = CartIntentAddResult(added: ["Milk"])

        let result = try await AddCartItemsIntent(names: "Milk and bread").perform(using: cart)

        #expect(cart.addedRequests == ["Milk and bread"])
        #expect(result == CartIntentAddResult(added: ["Milk"]))
    }

    @Test("REQ-WIDGET-060: the stop button ends the trip once")
    func endIntentEndsTheTrip() async {
        let cart = FakeCartIntentHandler()

        await EndShoppingTripIntent().perform(using: cart)

        #expect(cart.tripEnds == 1)
    }
}
