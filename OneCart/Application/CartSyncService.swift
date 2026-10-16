import CoreData
import Foundation
import Observation
import OSLog

enum CartSyncReason: String {
    case pull
    case appear
    case cloudImport
    case foreground
}

enum CartSyncOutcome: Equatable {
    case succeeded
    case skippedDebounce
    case cancelled
    case failed(String)
}

/// What one hard cart sync asks of the cart's owner, in this order: heal the owner's share ACL,
/// reset and refetch the cart, report its counts for the log, then check whether a guest's shared
/// cart is gone. The session conforms.
@MainActor
protocol CartRefreshing: AnyObject {
    func healOwnerShareACL() async
    /// A throw fails the sync; a `CancellationError` reports it cancelled.
    func hardRefreshCart() async throws
    var cartPurchaseCounts: (purchased: Int, total: Int) { get }
    func handleInviteeSharedCartGone() async
}

@MainActor
@Observable
final class CartSyncService {
    private(set) var isCartSyncing = false
    private(set) var contentRevision = 0

    private let persistence: PersistenceController
    private var pendingReason: CartSyncReason?
    private var isExclusiveRunning = false
    private var syncWaiters: [CheckedContinuation<CartSyncOutcome, Never>] = []
    private var lastAppearSyncAt: Date?
    private let clock: AppClock

    /// Weak: the session owns this service and is its refresher. Without one a sync only bumps
    /// the revision. Tests swap in a scripted refresher.
    @ObservationIgnored weak var refresher: (any CartRefreshing)?

    init(persistence: PersistenceController, clock: AppClock = .live, refresher: (any CartRefreshing)? = nil) {
        self.persistence = persistence
        self.clock = clock
        self.refresher = refresher
    }

    @discardableResult
    func syncCart(reason: CartSyncReason, debouncedAppear: Bool = true) async -> CartSyncOutcome {
        if reason == .appear, debouncedAppear {
            let appearedAt = clock.now()
            if let lastAppearSyncAt, appearedAt.timeIntervalSince(lastAppearSyncAt) < 2.5 {
                return .skippedDebounce
            }
            lastAppearSyncAt = appearedAt
        }

        pendingReason = Self.preferred(pending: pendingReason, incoming: reason)

        if isExclusiveRunning {
            let incoming = reason.rawValue
            let pendingLabel = pendingReason?.rawValue ?? "-"
            CartSyncLog.cart.info(
                "syncCart coalesce reason=\(incoming, privacy: .public) pending=\(pendingLabel, privacy: .public)"
            )
            return await withCheckedContinuation { continuation in
                syncWaiters.append(continuation)
            }
        }

        isExclusiveRunning = true
        defer {
            isCartSyncing = false
            isExclusiveRunning = false
        }

        var lastOutcome: CartSyncOutcome = .succeeded
        while let reasonToRun = takePendingReason() {
            isCartSyncing = Self.showsSyncChrome(for: reasonToRun)
            lastOutcome = await performSync(reason: reasonToRun)
        }
        let waiters = syncWaiters
        syncWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: lastOutcome)
        }
        return lastOutcome
    }

    private func takePendingReason() -> CartSyncReason? {
        let reason = pendingReason
        pendingReason = nil
        return reason
    }

    private static func showsSyncChrome(for reason: CartSyncReason) -> Bool {
        switch reason {
        case .pull, .appear, .foreground:
            true
        case .cloudImport:
            false
        }
    }

    private static func preferred(pending: CartSyncReason?, incoming: CartSyncReason) -> CartSyncReason {
        let rank: (CartSyncReason) -> Int = { reason in
            switch reason {
            case .pull: 4
            case .foreground: 3
            case .cloudImport: 2
            case .appear: 1
            }
        }
        guard let pending else { return incoming }
        return rank(incoming) >= rank(pending) ? incoming : pending
    }

    private func performSync(reason: CartSyncReason) async -> CartSyncOutcome {
        CartSyncLog.cart.info("syncCart start reason=\(reason.rawValue, privacy: .public)")

        await refresher?.healOwnerShareACL()
        await waitForCloudImportBestEffort(reason: reason)

        do {
            try await refresher?.hardRefreshCart()
            if let counts = refresher?.cartPurchaseCounts {
                let label = reason.rawValue
                CartSyncLog.cart.info(
                    "syncCart refresh purchased=\(counts.purchased)/\(counts.total) reason=\(label, privacy: .public)"
                )
            }
            contentRevision &+= 1
            await refresher?.handleInviteeSharedCartGone()
            let revision = contentRevision
            CartSyncLog.cart
                .info("syncCart done reason=\(reason.rawValue, privacy: .public) revision=\(revision)")
            return .succeeded
        } catch is CancellationError {
            CartSyncLog.cart.info(
                "syncCart cancelled reason=\(reason.rawValue, privacy: .public)"
            )
            return .cancelled
        } catch {
            let message = error.localizedDescription
            CartSyncLog.cart.error(
                "syncCart failed reason=\(reason.rawValue, privacy: .public) error=\(message, privacy: .public)"
            )
            return .failed(message)
        }
    }

    func bumpRevisionAfterLocalChange() {
        contentRevision &+= 1
    }

    private func waitForCloudImportBestEffort(reason: CartSyncReason) async {
        guard persistence.mirrorsToCloudKit else { return }
        let nanoseconds: UInt64 =
            switch reason {
            case .cloudImport:
                700_000_000
            case .pull, .appear, .foreground:
                250_000_000
            }
        try? await clock.sleep(nanoseconds: nanoseconds)
    }

    static func resetViewContextAndRefetch(
        persistence: PersistenceController,
        refetch: () throws -> Void
    ) throws {
        let context = persistence.container.viewContext
        context.reset()
        try refetch()
    }
}
