import Foundation
@testable import OneCart

/// ActivityKit stand-in: records every request, update and end, and keeps the running set
/// the way the system would.
@MainActor
final class FakeShoppingTripBackend: ShoppingTripActivityBackend {
    struct Requested {
        let attributes: ShoppingTripAttributes
        let state: ShoppingTripAttributes.ContentState
    }

    struct Updated: Equatable {
        let id: String
        let state: ShoppingTripAttributes.ContentState
    }

    struct Ended: Equatable {
        let id: String
        let state: ShoppingTripAttributes.ContentState?
        let dismissal: ShoppingTripDismissal
    }

    var areActivitiesEnabled = true
    var requestError: Error?
    private(set) var running: [ShoppingTripActivityRecord] = []
    private(set) var requested: [Requested] = []
    private(set) var updates: [Updated] = []
    private(set) var ended: [Ended] = []
    private var nextID = 1

    init(running: [ShoppingTripActivityRecord] = []) {
        self.running = running
    }

    func runningTrips() -> [ShoppingTripActivityRecord] {
        running
    }

    func request(
        attributes: ShoppingTripAttributes,
        state: ShoppingTripAttributes.ContentState
    ) throws -> String {
        if let requestError {
            throw requestError
        }
        let id = "trip-\(nextID)"
        nextID += 1
        requested.append(Requested(attributes: attributes, state: state))
        running.append(
            ShoppingTripActivityRecord(id: id, accountID: attributes.accountID, familyID: attributes.familyID)
        )
        return id
    }

    func update(id: String, state: ShoppingTripAttributes.ContentState) async {
        updates.append(Updated(id: id, state: state))
    }

    func end(id: String, state: ShoppingTripAttributes.ContentState?, dismissal: ShoppingTripDismissal) async {
        running.removeAll { $0.id == id }
        ended.append(Ended(id: id, state: state, dismissal: dismissal))
    }

    /// The user swiped the activity away on the Lock Screen.
    func dismissFromLockScreen(id: String) {
        running.removeAll { $0.id == id }
    }
}

/// The cart screen's view of the trip, for ViewModel and hosted-view tests.
@MainActor
@Observable
final class FakeShoppingTripController: ShoppingTripControlling {
    var isShoppingTripActive = false
    var areShoppingTripsAvailable = true
    private(set) var startCount = 0
    private(set) var endCount = 0

    func startShoppingTrip() async {
        startCount += 1
        isShoppingTripActive = true
    }

    func endShoppingTrip() async {
        endCount += 1
        isShoppingTripActive = false
    }
}
