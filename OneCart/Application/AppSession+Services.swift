import Foundation

// Declarative conformances only; a forwarding member exists where a protocol name
// has no exact counterpart on the session.

extension AppSession: SessionStateReading {
    var isActiveFamilySpacePrivate: Bool {
        guard let family = activeFamilySpace else { return false }
        return persistence.scope(for: family) == .private
    }
}

extension AppSession: CartEditing {}

extension AppSession: HistoryBrowsing {}

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
