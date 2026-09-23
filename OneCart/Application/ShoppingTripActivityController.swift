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

/// How an activity left the running set, as ActivityKit reports it.
enum ShoppingTripActivityPhase: Equatable, Sendable {
    /// No longer updated; the card may still show until it is dismissed.
    case ended
    /// Gone from the Lock Screen, for example swiped away by the user.
    case dismissed
}

/// The ActivityKit surface the controller needs; tests substitute a fake.
@MainActor
protocol ShoppingTripActivityBackend: AnyObject {
    var areActivitiesEnabled: Bool { get }
    /// Reports every trip activity that ends or is dismissed, whoever caused it.
    func observePhases(_ handler: @escaping @MainActor (String, ShoppingTripActivityPhase) -> Void)
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
    private var phaseHandler: (@MainActor (String, ShoppingTripActivityPhase) -> Void)?
    private var watchers: [String: Task<Void, Never>] = [:]

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func observePhases(_ handler: @escaping @MainActor (String, ShoppingTripActivityPhase) -> Void) {
        phaseHandler = handler
        Activity<ShoppingTripAttributes>.activities.forEach(watch)
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
        let activity = try Activity<ShoppingTripAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
        watch(activity)
        return activity.id
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

    /// Follows one activity until it is dismissed; a swipe on the Lock Screen reaches the
    /// app only through these state updates.
    private func watch(_ activity: Activity<ShoppingTripAttributes>) {
        let id = activity.id
        guard watchers[id] == nil else { return }
        watchers[id] = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                let phase: ShoppingTripActivityPhase? = switch state {
                case .ended: .ended
                case .dismissed: .dismissed
                default: nil
                }
                guard let phase else { continue }
                self?.phaseHandler?(id, phase)
                if phase == .dismissed {
                    break
                }
            }
            self?.watchers[id] = nil
        }
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
    /// The all-bought trip still shown until its delayed dismissal. ActivityKit no longer
    /// lists it as running, so Stop or a new trip must remove it by this id.
    @ObservationIgnored private var finishedTripID: String?
    /// Trips found running at launch. None is adopted until a snapshot names the signed-in
    /// account and active cart; the one matching it is kept and every other one ended.
    @ObservationIgnored private var launchTrips: [ShoppingTripActivityRecord]
    @ObservationIgnored private var tail: Task<Void, Never>?
    private let backend: any ShoppingTripActivityBackend
    private let now: () -> Date

    init(backend: any ShoppingTripActivityBackend, now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.now = now
        // The account and cart are unknown until the session restores them.
        launchTrips = backend.runningTrips()
        backend.observePhases { [weak self] id, phase in
            self?.activityLeft(id: id, phase: phase)
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
    /// empty, or everything on it is checked. Always queued: a start ahead in the queue
    /// may create the trip this snapshot must reach.
    func sync(with snapshot: WidgetCartSnapshot) {
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
        await adoptLaunchTrip(accountID: accountID, familyID: familyID)
        if let trip = activeTrip, !backend.runningTrips().contains(where: { $0.id == trip.id }) {
            // Swiped away before its state update reached the app; the new card replaces it.
            activeTrip = nil
            lastState = nil
        }
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
        let replaced = [activeTrip?.id, finishedTripID].compactMap(\.self)
        activeTrip = ShoppingTripActivityRecord(id: id, accountID: accountID, familyID: familyID)
        lastState = state
        finishedTripID = nil
        for previous in replaced {
            await backend.end(id: previous, state: nil, dismissal: .immediate)
        }
    }

    private func performSync(with snapshot: WidgetCartSnapshot) async {
        if let accountID = snapshot.accountID, let familyID = snapshot.familyID {
            await adoptLaunchTrip(accountID: accountID, familyID: familyID)
        }
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
            finishedTripID = trip.id
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
        let ids = Set(backend.runningTrips().map(\.id) + [activeTrip?.id, finishedTripID].compactMap(\.self))
        activeTrip = nil
        lastState = nil
        finishedTripID = nil
        launchTrips = []
        for id in ids.sorted() {
            await backend.end(id: id, state: nil, dismissal: .immediate)
        }
    }

    /// An activity ended or was dismissed outside the queue, most often by a swipe on the
    /// Lock Screen (REQ-WIDGET-060); the cart then offers to start a trip again.
    private func activityLeft(id: String, phase: ShoppingTripActivityPhase) {
        enqueue { [self] in
            if activeTrip?.id == id {
                activeTrip = nil
                lastState = nil
            }
            if phase == .dismissed, finishedTripID == id {
                finishedTripID = nil
            }
            launchTrips.removeAll { $0.id == id }
        }
    }

    /// Resolves the trips found at launch against the signed-in account and active cart
    /// (REQ-WIDGET-050): the first match becomes the trip, the rest are ended.
    private func adoptLaunchTrip(accountID: UUID, familyID: UUID) async {
        guard !launchTrips.isEmpty else { return }
        let running = Set(backend.runningTrips().map(\.id))
        let found = launchTrips.filter { running.contains($0.id) }
        launchTrips = []
        if activeTrip == nil {
            activeTrip = found.first { $0.accountID == accountID && $0.familyID == familyID }
        }
        for trip in found where trip.id != activeTrip?.id {
            await backend.end(id: trip.id, state: nil, dismissal: .immediate)
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
