import Foundation
@testable import OneCart

/// ActivityKit stand-in: records every request, update and end, and keeps the running set
/// the way the system would.
@MainActor
final class FakeShoppingTripBackend: ShoppingTripActivityBackend {
    struct Requested {
        let attributes: ShoppingTripAttributes
        let state: ShoppingTripAttributes.ContentState
        let staleDate: Date
    }

    struct Updated: Equatable {
        let id: String
        let state: ShoppingTripAttributes.ContentState
        let staleDate: Date
    }

    struct Ended: Equatable {
        let id: String
        let state: ShoppingTripAttributes.ContentState?
        let dismissal: ShoppingTripDismissal
    }

    var areActivitiesEnabled = true
    var requestError: Error?
    /// While set, `end` waits for `releaseEnds()`, which holds every later queued operation.
    var holdsEnds = false
    private(set) var heldEnds = 0
    private var endWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var running: [ShoppingTripActivityRecord] = []
    private(set) var requested: [Requested] = []
    private(set) var updates: [Updated] = []
    private(set) var ended: [Ended] = []
    /// Ended with a delayed dismissal: no longer running, still on the Lock Screen.
    private(set) var lingering: [String] = []
    private var nextID = 1
    private var phaseHandler: (@MainActor (String, ShoppingTripActivityPhase) -> Void)?

    /// Every card the Lock Screen shows: running trips and finished ones not yet dismissed.
    var shownIDs: [String] {
        running.map(\.id) + lingering
    }

    init(running: [ShoppingTripActivityRecord] = []) {
        self.running = running
    }

    func observePhases(_ handler: @escaping @MainActor (String, ShoppingTripActivityPhase) -> Void) {
        phaseHandler = handler
    }

    func runningTrips() -> [ShoppingTripActivityRecord] {
        running
    }

    func request(
        attributes: ShoppingTripAttributes,
        state: ShoppingTripAttributes.ContentState,
        staleDate: Date
    ) throws -> String {
        if let requestError {
            throw requestError
        }
        let id = "trip-\(nextID)"
        nextID += 1
        requested.append(Requested(attributes: attributes, state: state, staleDate: staleDate))
        running.append(
            ShoppingTripActivityRecord(id: id, accountID: attributes.accountID, familyID: attributes.familyID)
        )
        return id
    }

    func update(id: String, state: ShoppingTripAttributes.ContentState, staleDate: Date) async {
        updates.append(Updated(id: id, state: state, staleDate: staleDate))
    }

    func end(id: String, state: ShoppingTripAttributes.ContentState?, dismissal: ShoppingTripDismissal) async {
        if holdsEnds {
            heldEnds += 1
            await withCheckedContinuation { endWaiters.append($0) }
        }
        let wasShown = shownIDs.contains(id)
        running.removeAll { $0.id == id }
        lingering.removeAll { $0 == id }
        if wasShown, case .after = dismissal {
            lingering.append(id)
        }
        ended.append(Ended(id: id, state: state, dismissal: dismissal))
        guard wasShown else { return }
        // ActivityKit reports the app's own ends through the same state updates.
        phaseHandler?(id, .ended)
        if dismissal == .immediate {
            phaseHandler?(id, .dismissed)
        }
    }

    func releaseEnds() {
        holdsEnds = false
        let waiters = endWaiters
        endWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// Lets queued work run until `condition` holds; the fake's own tasks run on the main actor.
    func yield(until condition: () -> Bool) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
    }

    /// The user swiped the activity away on the Lock Screen. `notifies: false` models a state
    /// update the app has not received yet.
    func dismissFromLockScreen(id: String, notifies: Bool = true) {
        running.removeAll { $0.id == id }
        lingering.removeAll { $0 == id }
        if notifies {
            phaseHandler?(id, .dismissed)
        }
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
