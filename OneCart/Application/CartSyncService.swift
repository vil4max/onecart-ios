import CoreData
import Foundation
import OSLog

enum CartSyncReason: String {
    case pull
    case appear
    case cloudImport
    case foreground
    case afterToggle
    case afterMutation
}

enum CartSyncOutcome: Equatable {
    case succeeded
    case skippedDebounce
    case failed(String)
}

@MainActor
final class CartSyncService: ObservableObject {
    @Published private(set) var isCartSyncing = false
    @Published private(set) var contentRevision = 0

    private let persistence: PersistenceController
    private var pendingReason: CartSyncReason?
    private var isExclusiveRunning = false
    private var lastAppearSyncAt: Date?

    var onHardRefresh: (() async throws -> Void)?
    var onOwnerACLHeal: (() async -> Void)?
    var onInviteeSharedGone: (() async -> Void)?
    var purchasedCountProvider: (() -> (purchased: Int, total: Int))?

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    @discardableResult
    func syncCart(reason: CartSyncReason, debouncedAppear: Bool = true) async -> CartSyncOutcome {
        if reason == .appear, debouncedAppear {
            if let lastAppearSyncAt, Date().timeIntervalSince(lastAppearSyncAt) < 2.5 {
                return .skippedDebounce
            }
            lastAppearSyncAt = Date()
        }

        pendingReason = Self.preferred(pending: pendingReason, incoming: reason)

        if isExclusiveRunning {
            let pendingLabel = pendingReason?.rawValue ?? "-"
            CartSyncLog.cart.info(
                "syncCart coalesce reason=\(reason.rawValue, privacy: .public) pending=\(pendingLabel, privacy: .public)"
            )
            while isExclusiveRunning {
                await Task.yield()
            }
            if let leftover = pendingReason {
                return await syncCart(reason: leftover, debouncedAppear: false)
            }
            return .succeeded
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
        case .cloudImport, .afterToggle, .afterMutation:
            false
        }
    }

    private static func preferred(pending: CartSyncReason?, incoming: CartSyncReason) -> CartSyncReason {
        let rank: (CartSyncReason) -> Int = { reason in
            switch reason {
            case .pull: 4
            case .foreground: 3
            case .cloudImport, .afterToggle, .afterMutation: 2
            case .appear: 1
            }
        }
        guard let pending else { return incoming }
        return rank(incoming) >= rank(pending) ? incoming : pending
    }

    private func performSync(reason: CartSyncReason) async -> CartSyncOutcome {
        CartSyncLog.cart.info("syncCart start reason=\(reason.rawValue, privacy: .public)")

        await onOwnerACLHeal?()
        await waitForCloudImportBestEffort(reason: reason)

        do {
            try await onHardRefresh?()
            if let counts = purchasedCountProvider?() {
                CartSyncLog.cart.info(
                    "syncCart refresh purchased=\(counts.purchased) total=\(counts.total) reason=\(reason.rawValue, privacy: .public)"
                )
            }
            contentRevision &+= 1
            await onInviteeSharedGone?()
            let revision = contentRevision
            CartSyncLog.cart
                .info("syncCart done reason=\(reason.rawValue, privacy: .public) revision=\(revision)")
            return .succeeded
        } catch is CancellationError {
            CartSyncLog.cart.info(
                "syncCart cancelled reason=\(reason.rawValue, privacy: .public)"
            )
            return .skippedDebounce
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
        guard !persistence.inMemory else { return }
        let nanoseconds: UInt64 = switch reason {
        case .cloudImport, .afterToggle, .afterMutation:
            700_000_000
        case .pull, .appear, .foreground:
            250_000_000
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
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
