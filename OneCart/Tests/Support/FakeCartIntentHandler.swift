import Foundation
@testable import OneCart

/// Records what the intents forward, standing in for the session `@Dependency` resolves in the app.
@MainActor
final class FakeCartIntentHandler: CartIntentHandling {
    private(set) var addedRequests: [String] = []
    private(set) var purchases: [WidgetPurchaseRequest] = []
    private(set) var remainingReads = 0
    private(set) var tripStarts = 0
    private(set) var tripEnds = 0
    var addResult = CartIntentAddResult()

    func handleAddItems(_ raw: String) async throws -> CartIntentAddResult {
        addedRequests.append(raw)
        return addResult
    }

    func handleRemainingItems() async throws -> CartIntentRemaining {
        remainingReads += 1
        return CartIntentRemaining(totalCount: 0, names: [])
    }

    func handleStartShoppingTrip() async throws {
        tripStarts += 1
    }

    func handleWidgetPurchase(_ request: WidgetPurchaseRequest) async throws {
        purchases.append(request)
    }

    func handleEndShoppingTrip() async {
        tripEnds += 1
    }
}
