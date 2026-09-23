import Foundation

/// Why a Siri or Shortcuts request could not reach the cart; Siri speaks the description.
enum CartIntentError: LocalizedError, Equatable {
    case signedOut
    case readOnly
    case emptyName
    case failed
    /// The app's startup failed; unlike `signedOut`, the user has nothing to sign in to.
    case unavailable

    var errorDescription: String? {
        switch self {
        case .signedOut:
            String(localized: "intent.error.signed_out")
        case .readOnly:
            String(localized: "intent.error.read_only")
        case .emptyName:
            String(localized: "intent.error.empty_name")
        case .failed:
            String(localized: "sync.generic_failure")
        case .unavailable:
            String(localized: "intent.error.unavailable")
        }
    }
}

struct CartIntentAddResult: Equatable, Sendable {
    /// New lines, in the order they were said.
    var added: [String] = []
    /// Names that already lived on the cart and were left as they are (REQ-CART-090).
    var alreadyOnCart: [String] = []
}

struct CartIntentRemaining: Equatable, Sendable {
    let totalCount: Int
    /// To-buy names in cart order.
    let names: [String]
}

enum CartIntentNames {
    /// One request may carry several names ("milk, bread; eggs"). Blank parts are dropped and a
    /// name said twice is added once.
    static func split(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(FamilyCartMerge.normalizedProductName($0)).inserted }
    }
}

/// How long a Siri request waits for the app's startup before it reports the app unavailable
/// (REQ-SIRI-040). The clock is injectable so tests decide when time runs out.
@MainActor
struct CartIntentDeadline {
    static let startupLimit: Duration = .seconds(10)

    let end: ContinuousClock.Instant
    let now: @MainActor @Sendable () -> ContinuousClock.Instant
    let sleep: @MainActor @Sendable (Duration) async throws -> Void

    static func live(limit: Duration = startupLimit) -> CartIntentDeadline {
        CartIntentDeadline(
            end: .now + limit,
            now: { .now },
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    var hasPassed: Bool {
        now() >= end
    }

    /// Waits for `operation` until the deadline and reports whether it finished first. The
    /// operation runs in its own task and is never cancelled: startup goes on after Siri gave up.
    func wait(for operation: @escaping @MainActor @Sendable () async -> Void) async -> Bool {
        let work = Task { @MainActor in await operation() }
        let remaining = end - now()
        guard remaining > .zero else { return false }
        let outcome = FirstOutcome()
        return await withCheckedContinuation { continuation in
            outcome.continuation = continuation
            let timer = Task { @MainActor in
                try? await sleep(remaining)
                outcome.resolve(false)
            }
            Task { @MainActor in
                await work.value
                timer.cancel()
                outcome.resolve(true)
            }
        }
    }

    /// Resumes the waiting request once, with whichever of the work and the timer ends first.
    @MainActor
    private final class FirstOutcome {
        var continuation: CheckedContinuation<Bool, Never>?

        func resolve(_ finished: Bool) {
            continuation?.resume(returning: finished)
            continuation = nil
        }
    }
}

extension AppSession {
    /// Adds name-only lines to the cart the cart screen shows (REQ-SIRI-010).
    func addItemsFromIntent(
        _ raw: String,
        deadline: CartIntentDeadline = .live()
    ) async throws -> CartIntentAddResult {
        let names = CartIntentNames.split(raw)
        guard !names.isEmpty else { throw CartIntentError.emptyName }
        let list = try await cartListForIntent(deadline: deadline)
        guard canEdit else { throw CartIntentError.readOnly }
        guard let listID = list.id else { throw CartIntentError.failed }

        var result = CartIntentAddResult()
        for name in names {
            let existingIDs = Set(products(inListID: listID).compactMap(\.id))
            guard let productID = await addProduct(to: list, draft: .nameOnly(name)) else {
                throw CartIntentError.failed
            }
            if existingIDs.contains(productID) {
                result.alreadyOnCart.append(name)
            } else {
                result.added.append(name)
            }
        }
        return result
    }

    /// What is still to buy, read without changing the cart (REQ-SIRI-020).
    func remainingItemsForIntent(deadline: CartIntentDeadline = .live()) async throws -> CartIntentRemaining {
        let list = try await cartListForIntent(deadline: deadline)
        let lines = list.id.map { products(inListID: $0) } ?? []
        return CartIntentRemaining(
            totalCount: lines.count,
            names: lines.filter { !$0.isPurchasedValue }.map(\.displayName)
        )
    }

    /// Starts the shopping trip Live Activity (REQ-SIRI-030, REQ-WIDGET-040).
    func beginShoppingTrip() async throws {
        guard canEdit else { throw CartIntentError.readOnly }
        let snapshot = makeWidgetSnapshot(theme: preferences.theme, accent: preferences.accentColor)
        try await shoppingTrip.start(with: snapshot)
    }

    func startShoppingTripFromIntent(deadline: CartIntentDeadline = .live()) async throws {
        _ = try await cartListForIntent(deadline: deadline)
        try await beginShoppingTrip()
    }

    /// Siri may launch the app in the background: finish startup and the household cart first.
    /// A start that failed is run again here, so one bad launch does not refuse every request.
    /// Siri gets an answer within the deadline; a startup still running then goes on alone.
    private func cartListForIntent(deadline: CartIntentDeadline) async throws -> ShoppingListEntity {
        guard await deadline.wait(for: { await self.start(retryingFailure: true) }) else {
            throw CartIntentError.unavailable
        }
        guard !startFailed else { throw CartIntentError.unavailable }
        guard account != nil, !needsWelcome else { throw CartIntentError.signedOut }
        if activeFamilySpace == nil {
            await ensureHouseholdCartIfNeeded()
        }
        // The timer and the work can finish in the same turn; nothing may change the cart or
        // start a trip after the time Siri was promised an answer by.
        guard !deadline.hasPassed else { throw CartIntentError.unavailable }
        guard let list = CartViewModel.primaryList(in: activeLists) else { throw CartIntentError.failed }
        return list
    }
}
