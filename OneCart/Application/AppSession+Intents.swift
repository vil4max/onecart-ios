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

extension AppSession {
    /// Adds name-only lines to the cart the cart screen shows (REQ-SIRI-010).
    func addItemsFromIntent(_ raw: String) async throws -> CartIntentAddResult {
        let names = CartIntentNames.split(raw)
        guard !names.isEmpty else { throw CartIntentError.emptyName }
        let list = try await cartListForIntent()
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
    func remainingItemsForIntent() async throws -> CartIntentRemaining {
        let list = try await cartListForIntent()
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

    func startShoppingTripFromIntent() async throws {
        _ = try await cartListForIntent()
        try await beginShoppingTrip()
    }

    /// Siri may launch the app in the background: finish startup and the household cart first.
    /// A start that failed is run again here, so one bad launch does not refuse every request.
    private func cartListForIntent() async throws -> ShoppingListEntity {
        await start(retryingFailure: true)
        guard !startFailed else { throw CartIntentError.unavailable }
        guard account != nil, !needsWelcome else { throw CartIntentError.signedOut }
        if activeFamilySpace == nil {
            await ensureHouseholdCartIfNeeded()
        }
        guard let list = CartViewModel.primaryList(in: activeLists) else { throw CartIntentError.failed }
        return list
    }
}
