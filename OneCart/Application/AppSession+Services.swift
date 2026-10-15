import Foundation

// Declarative conformances only; a forwarding member exists where a protocol name
// has no exact counterpart on the session. The screens read value snapshots
// (`cartLists`, `cartItems`, `historyLines`); the session's own entity accessors stay internal
// to the application layer.

extension AppSession: SessionStateReading {
    var isActiveFamilySpacePrivate: Bool {
        guard let family = activeFamilySpace else { return false }
        return persistence.scope(for: family) == .private
    }

    var cartLists: [CartList] {
        cartContent.cartLists
    }

    var hasActiveCartLists: Bool {
        !cartContent.activeLists.isEmpty
    }

    func cartItems(inListID listID: UUID) -> [CartItem] {
        cartContent.cartItems(inListID: listID)
    }
}

extension AppSession: CartEditing {}

/// The conformance itself is declared in `AppSession.swift`: the protocol refines `Sendable`.
extension AppSession {
    func handleAddItems(_ raw: String) async throws -> CartIntentAddResult {
        try await addItemsFromIntent(raw)
    }

    func handleRemainingItems() async throws -> CartIntentRemaining {
        try await remainingItemsForIntent()
    }

    func handleStartShoppingTrip() async throws {
        try await startShoppingTripFromIntent()
    }

    func handleWidgetPurchase(_ request: WidgetPurchaseRequest) async throws {
        try await performWidgetPurchase(request)
    }

    func handleEndShoppingTrip() async {
        await endShoppingTrip()
    }
}

extension AppSession: HistoryBrowsing {
    var historyLines: [HistoryLine] {
        cartContent.historyLines
    }
}

extension AppSession: MembershipManaging {}

extension AppSession: AccountManaging {}

extension AppSession: WelcomeSigningIn {}

extension AppSession: HouseholdCartBootstrapping {}

extension AppSession: AlertPresenting {}

extension AppSession: MainTabRouting {
    func clearPreferredMainTab() {
        preferredMainTab = nil
    }
}
