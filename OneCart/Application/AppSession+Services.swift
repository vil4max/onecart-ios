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
