import Foundation
@testable import OneCart

extension CloudSyncCoordinator {
    /// A coordinator whose connectivity never reports, for tests that drive reloads only.
    convenience init(
        persistence: PersistenceController,
        cartSync: CartSyncService,
        clock: AppClock = .live,
        context: any CloudSyncContext
    ) {
        self.init(
            persistence: persistence,
            cartSync: cartSync,
            connectivity: FakeConnectivityMonitor(),
            clock: clock,
            context: context
        )
    }
}
