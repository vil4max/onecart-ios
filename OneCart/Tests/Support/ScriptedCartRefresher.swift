import Foundation
@testable import OneCart

/// Stands in for the session as a `CartSyncService` refresher: the hard refresh runs the given
/// script and the other steps do nothing. The service holds its refresher weakly, so a test
/// keeps this alive for as long as it syncs.
@MainActor
final class ScriptedCartRefresher: CartRefreshing {
    private let hardRefresh: () async throws -> Void

    init(hardRefresh: @escaping () async throws -> Void = {}) {
        self.hardRefresh = hardRefresh
    }

    func healOwnerShareACL() async {}

    func hardRefreshCart() async throws {
        try await hardRefresh()
    }

    var cartPurchaseCounts: (purchased: Int, total: Int) {
        (0, 0)
    }

    func handleInviteeSharedCartGone() async {}
}
