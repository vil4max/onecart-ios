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
    private var syncTask: Task<CartSyncOutcome, Never>?
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

        syncTask?.cancel()
        let work = Task { @MainActor in
            await performSync(reason: reason)
        }
        syncTask = work
        return await work.value
    }

    private func performSync(reason: CartSyncReason) async -> CartSyncOutcome {
        guard !Task.isCancelled else { return .skippedDebounce }
        isCartSyncing = true
        defer { isCartSyncing = false }

        CartSyncLog.cart.info("syncCart start reason=\(reason.rawValue, privacy: .public)")

        await onOwnerACLHeal?()
        await waitForCloudImportBestEffort()

        do {
            try await onHardRefresh?()
            if let counts = purchasedCountProvider?() {
                CartSyncLog.cart.info(
                    "syncCart refresh purchased=\(counts.purchased) total=\(counts.total) reason=\(reason.rawValue, privacy: .public)"
                )
            }
            contentRevision &+= 1
            await onInviteeSharedGone?()
            CartSyncLog.cart
                .info("syncCart done reason=\(reason.rawValue, privacy: .public) revision=\(self.contentRevision)")
            return .succeeded
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

    private func waitForCloudImportBestEffort() async {
        guard !persistence.inMemory else { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
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
