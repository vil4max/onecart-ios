import Foundation

/// Why a Siri or Shortcuts request could not reach the cart. App Intents wraps a thrown error
/// that provides a `LocalizedStringResource` and speaks it in the language of the request.
enum CartIntentError: LocalizedError, CustomLocalizedStringResourceConvertible, Equatable {
    case signedOut
    case readOnly
    case emptyName
    case failed
    /// The app's startup failed; unlike `signedOut`, the user has nothing to sign in to.
    case unavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut:
            "intent.error.signed_out"
        case .readOnly:
            "intent.error.read_only"
        case .emptyName:
            "intent.error.empty_name"
        case .failed:
            // Every `.failed` is local (no cart, or a save that did not land); iCloud runs later.
            "intent.error.failed"
        case .unavailable:
            "intent.error.unavailable"
        }
    }

    var errorDescription: String? {
        String(localized: localizedStringResource)
    }
}

struct CartIntentAddResult: Equatable, Sendable {
    /// New lines, in the order they were said.
    var added: [String] = []
    /// Names that already lived on the cart and were left as they are (REQ-CART-090).
    var alreadyOnCart: [String] = []
    /// Names whose save did not land.
    var failed: [String] = []

    enum Outcome {
        case added
        case alreadyOnCart
        case failed
    }

    /// Adds the names one by one. A name that fails is reported and the rest still go in, because
    /// the names before it are already saved; only a request where nothing landed is an error.
    @MainActor
    static func adding(
        _ names: [String],
        using add: @MainActor (String) async -> Outcome
    ) async throws -> CartIntentAddResult {
        var result = CartIntentAddResult()
        for name in names {
            switch await add(name) {
            case .added:
                result.added.append(name)
            case .alreadyOnCart:
                result.alreadyOnCart.append(name)
            case .failed:
                result.failed.append(name)
            }
        }
        if result.added.isEmpty, result.alreadyOnCart.isEmpty {
            throw CartIntentError.failed
        }
        return result
    }
}

struct CartIntentRemaining: Equatable, Sendable {
    let totalCount: Int
    /// To-buy names in the order the cart screen shows them.
    let names: [String]
}

/// Marks cart work done for a Siri or Shortcuts request. Siri speaks its own result, so a cart
/// mutation inside it queues no in-app alert, which would otherwise show up later, out of context.
enum CartIntentContext {
    @TaskLocal static var isActive = false
}

enum CartIntentNames {
    /// Standalone words that join dictated names (owner decision): Russian, Ukrainian, English.
    private static let andWords: Set<String> = ["и", "і", "and"]

    /// One request may carry several names ("milk, bread; eggs", "молоко и хлеб"). Blank parts
    /// are dropped and a name said twice is added once.
    static func split(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .flatMap(splitOnAndWords)
            .filter { !$0.isEmpty && seen.insert(FamilyCartMerge.normalizedProductName($0)).inserted }
    }

    /// Splits on whole words only, so a name that merely contains those letters stays whole.
    private static func splitOnAndWords(_ part: Substring) -> [String] {
        var names: [String] = []
        var words: [Substring] = []
        for word in part.split(whereSeparator: \.isWhitespace) {
            if andWords.contains(word.lowercased()) {
                names.append(words.joined(separator: " "))
                words = []
            } else {
                words.append(word)
            }
        }
        names.append(words.joined(separator: " "))
        return names
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

        return try await CartIntentContext.$isActive.withValue(true) {
            try await CartIntentAddResult.adding(names) { name in
                // Checked here, in the same turn as the mutation's own check, so a cart that turned
                // read-only mid-request is reported as a failed name rather than as an app alert.
                guard canEdit else { return .failed }
                let existingIDs = Set(products(inListID: listID).compactMap(\.id))
                guard let productID = await addProduct(to: list, draft: .nameOnly(name)) else {
                    return .failed
                }
                return existingIDs.contains(productID) ? .alreadyOnCart : .added
            }
        }
    }

    /// What is still to buy, read without changing the cart (REQ-SIRI-020).
    func remainingItemsForIntent(deadline: CartIntentDeadline = .live()) async throws -> CartIntentRemaining {
        let list = try await cartListForIntent(deadline: deadline)
        let lines = list.id.map { products(inListID: $0) } ?? []
        // The grouping the cart screen draws its to-buy sections with (CartViewModel.toBuySections).
        let toBuy = ProductCategory.groupedSections(from: lines.filter { !$0.isPurchasedValue }) { $0.categoryValue }
        return CartIntentRemaining(
            totalCount: lines.count,
            names: toBuy.flatMap(\.items).map(\.displayName)
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
        // Joins a setup the cart screen already started instead of finding no cart.
        if activeFamilySpace == nil {
            guard await deadline.wait(for: { await self.ensureHouseholdCartIfNeeded() }) else {
                throw CartIntentError.unavailable
            }
        }
        // The timer and the work can finish in the same turn; nothing may change the cart or
        // start a trip after the time Siri was promised an answer by.
        guard !deadline.hasPassed else { throw CartIntentError.unavailable }
        guard let list = CartViewModel.primaryList(in: activeLists) else { throw CartIntentError.failed }
        return list
    }
}
