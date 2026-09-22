import ActivityKit
import Foundation

/// One running shopping-trip Live Activity and the cart it belongs to.
struct ShoppingTripActivityRecord: Equatable, Sendable {
    let id: String
    let accountID: UUID
    let familyID: UUID
}

enum ShoppingTripDismissal: Equatable, Sendable {
    case immediate
    case after(Date)
}

enum ShoppingTripError: LocalizedError, Equatable {
    /// Live Activities are off for OneCart, or the system refused the request.
    case unavailable
    /// Nothing is left to buy on the cart, so there is no trip to follow.
    case nothingToBuy

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "trip.start_unavailable")
        case .nothingToBuy:
            String(localized: "trip.start_nothing_to_buy")
        }
    }
}

/// The ActivityKit surface the controller needs; tests substitute a fake.
@MainActor
protocol ShoppingTripActivityBackend: AnyObject {
    var areActivitiesEnabled: Bool { get }
    func runningTrips() -> [ShoppingTripActivityRecord]
    func request(
        attributes: ShoppingTripAttributes,
        state: ShoppingTripAttributes.ContentState
    ) throws -> String
    func update(id: String, state: ShoppingTripAttributes.ContentState) async
    func end(id: String, state: ShoppingTripAttributes.ContentState?, dismissal: ShoppingTripDismissal) async
}

@MainActor
final class LiveShoppingTripActivityBackend: ShoppingTripActivityBackend {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func runningTrips() -> [ShoppingTripActivityRecord] {
        Activity<ShoppingTripAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map {
                ShoppingTripActivityRecord(
                    id: $0.id,
                    accountID: $0.attributes.accountID,
                    familyID: $0.attributes.familyID
                )
            }
    }

    func request(
        attributes: ShoppingTripAttributes,
        state: ShoppingTripAttributes.ContentState
    ) throws -> String {
        try Activity<ShoppingTripAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        ).id
    }

    func update(id: String, state: ShoppingTripAttributes.ContentState) async {
        guard let activity = Self.activity(id: id) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(id: String, state: ShoppingTripAttributes.ContentState?, dismissal: ShoppingTripDismissal) async {
        guard let activity = Self.activity(id: id) else { return }
        let policy: ActivityUIDismissalPolicy = switch dismissal {
        case .immediate:
            .immediate
        case let .after(date):
            .after(date)
        }
        await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy)
    }

    private nonisolated static func activity(id: String) -> Activity<ShoppingTripAttributes>? {
        Activity<ShoppingTripAttributes>.activities.first { $0.id == id }
    }
}

/// Starts, follows and ends the shopping trip from the widget snapshot (REQ-WIDGET-040…060).
/// Operations run one after another so a slow ActivityKit update can never land after a
/// newer one or after the trip ended.
@MainActor
@Observable
final class ShoppingTripActivityController {
    /// How long the finished trip stays on the Lock Screen once every line is checked.
    static let completedDismissalDelay: TimeInterval = 5 * 60

    private(set) var activeTrip: ShoppingTripActivityRecord?

    @ObservationIgnored private var lastState: ShoppingTripAttributes.ContentState?
    @ObservationIgnored private var tail: Task<Void, Never>?
    private let backend: any ShoppingTripActivityBackend
    private let now: () -> Date

    init(backend: any ShoppingTripActivityBackend, now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.now = now
        // A relaunched app adopts the trip it started before; extra ones are leftovers.
        let running = backend.runningTrips()
        activeTrip = running.first
        let leftovers = running.dropFirst().map(\.id)
        if !leftovers.isEmpty {
            enqueue { [backend] in
                for id in leftovers {
                    await backend.end(id: id, state: nil, dismissal: .immediate)
                }
            }
        }
    }

    var isActive: Bool {
        activeTrip != nil
    }

    var isAvailable: Bool {
        backend.areActivitiesEnabled
    }

    func start(with snapshot: WidgetCartSnapshot) async throws {
        let result = await enqueue { [self] () async -> Result<Void, any Error> in
            do {
                try await performStart(with: snapshot)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        try result.get()
    }

    /// Follows the cart; ends the trip when its cart or account is gone, the cart is
    /// empty, or everything on it is checked.
    func sync(with snapshot: WidgetCartSnapshot) {
        guard activeTrip != nil else { return }
        enqueue { [self] in
            await performSync(with: snapshot)
        }
    }

    /// Queues the end at once, so a caller that cannot await (sign out) still orders it
    /// before any later start.
    @discardableResult
    func end() -> Task<Void, Never> {
        enqueue { [self] in
            await performEnd()
        }
    }

    /// Resolves once every queued operation finished; tests await it.
    func settle() async {
        await tail?.value
    }

    // MARK: - Operations

    private func performStart(with snapshot: WidgetCartSnapshot) async throws {
        guard let accountID = snapshot.accountID, let familyID = snapshot.familyID else {
            throw ShoppingTripError.unavailable
        }
        guard snapshot.remainingCount > 0 else { throw ShoppingTripError.nothingToBuy }
        if let activeTrip, activeTrip.accountID == accountID, activeTrip.familyID == familyID {
            return
        }
        guard backend.areActivitiesEnabled else { throw ShoppingTripError.unavailable }
        let state = ShoppingTripAttributes.ContentState(snapshot: snapshot)
        let id: String
        do {
            id = try backend.request(
                attributes: ShoppingTripAttributes(accountID: accountID, familyID: familyID),
                state: state
            )
        } catch {
            throw ShoppingTripError.unavailable
        }
        let previous = activeTrip
        activeTrip = ShoppingTripActivityRecord(id: id, accountID: accountID, familyID: familyID)
        lastState = state
        if let previous {
            await backend.end(id: previous.id, state: nil, dismissal: .immediate)
        }
    }

    private func performSync(with snapshot: WidgetCartSnapshot) async {
        guard let trip = activeTrip else { return }
        // Swiping the activity away on the Lock Screen ends it outside the app.
        guard backend.runningTrips().contains(where: { $0.id == trip.id }) else {
            activeTrip = nil
            lastState = nil
            return
        }
        guard snapshot.accountID == trip.accountID, snapshot.familyID == trip.familyID, !snapshot.isEmpty else {
            await performEnd()
            return
        }
        let state = ShoppingTripAttributes.ContentState(snapshot: snapshot)
        if state.isAllPurchased {
            activeTrip = nil
            lastState = nil
            await backend.end(
                id: trip.id,
                state: state,
                dismissal: .after(now().addingTimeInterval(Self.completedDismissalDelay))
            )
            return
        }
        guard state != lastState else { return }
        lastState = state
        await backend.update(id: trip.id, state: state)
    }

    private func performEnd() async {
        let ids = Set(backend.runningTrips().map(\.id) + [activeTrip?.id].compactMap(\.self))
        activeTrip = nil
        lastState = nil
        for id in ids.sorted() {
            await backend.end(id: id, state: nil, dismissal: .immediate)
        }
    }

    @discardableResult
    private func enqueue<T: Sendable>(_ operation: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        tail = Task { @MainActor in
            _ = await task.value
        }
        return task
    }
}
