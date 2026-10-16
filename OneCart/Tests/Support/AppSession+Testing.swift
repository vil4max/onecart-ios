import Foundation
@testable import OneCart

/// Session entry points only tests need: production reaches these states through the bootstrapper.
extension AppSession {
    func bootstrapTestingSession(account: OneCartAccount) throws {
        self.account = account
        try reload()
    }

    func offerSharedCartJoinIfNeededForTesting() async throws {
        guard let account else { return }
        try await offerSharedCartJoinIfNeeded(for: account)
    }

    /// The intents and the widget queue live in the session's collaborators; the suites drive
    /// them through the session they build.
    func addItemsFromIntent(
        _ raw: String,
        deadline: CartIntentDeadline = .live()
    ) async throws -> CartIntentAddResult {
        try await intentHandler.addItemsFromIntent(raw, deadline: deadline)
    }

    func remainingItemsForIntent(deadline: CartIntentDeadline = .live()) async throws -> CartIntentRemaining {
        try await intentHandler.remainingItemsForIntent(deadline: deadline)
    }

    func startShoppingTripFromIntent(deadline: CartIntentDeadline = .live()) async throws {
        try await intentHandler.startShoppingTripFromIntent(deadline: deadline)
    }

    func performWidgetPurchase(_ request: WidgetPurchaseRequest) async throws {
        try await intentHandler.handleWidgetPurchase(request)
    }

    func makeWidgetSnapshot(accent: AppAccentColor) -> WidgetCartSnapshot {
        widgetSync.makeWidgetSnapshot(accent: accent)
    }

    var categoryRefinementTasks: [UUID: Task<Void, Never>] {
        cartMutations.categoryRefinementTasks
    }

    /// The leave recovery lives in `MembershipService`. A test that runs the recovery itself
    /// hands its task over, so the suite cleanup awaits it.
    var leaveRecoveryTask: Task<Void, Never>? {
        get { membership.leaveRecoveryTask }
        set {
            guard let newValue else { return membership.cancelLeaveRecovery() }
            membership.trackLeaveRecovery(newValue)
        }
    }

    var leaveRecoveryPassCount: Int {
        membership.leaveRecoveryPassCount
    }

    nonisolated static let leaveRecoveryPasses = MembershipService.leaveRecoveryPasses
    nonisolated static let leaveRecoveryInterval = MembershipService.leaveRecoveryInterval

    func recoverAfterLeaveTimeout(latePurgeCompletions: AsyncStream<Void>) async {
        await membership.recoverAfterLeaveTimeout(latePurgeCompletions: latePurgeCompletions)
    }

    func setActiveFamilySpace(_ space: FamilySpace) {
        guard let id = space.id, let account else { return }
        defaults.set(id.uuidString, forKey: activeFamilyKey(accountID: account.id))
        do {
            try reload(preferredFamilySpaceID: id)
            Task { await refreshFamilyMetadata(showErrors: false) }
        } catch {
            show(error)
        }
    }
}
