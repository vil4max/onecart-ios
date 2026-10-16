import CoreData
import Foundation

struct WidgetPurchaseDependencies {
    let widgetStore: any WidgetSnapshotStoring
    let shoppingTrip: ShoppingTripActivityController
    let cartContent: CartContentStore
    let cartItems: any CartItemsRepository
    let cartSync: CartSyncService
    let mutations: CartMutationService
}

/// Writes the widget snapshot the widgets and the shopping trip draw, and replays the purchases
/// the widgets and the Live Activity queue. Owns the one drain of that queue in flight.
@MainActor
final class WidgetPurchaseSync {
    /// REQ-WIDGET-010: the snapshot carries up to six needed and two completed lines.
    static let widgetNeededLimit = 6
    static let widgetCompletedLimit = 2

    /// REQ-SHELL-030: the widgets follow the device appearance. `themeRaw` stays in the
    /// snapshot so snapshots written by older builds still decode.
    static let widgetThemeRaw = "system"

    /// The drain in flight; a second caller joins it instead of replaying the queue twice.
    private(set) var widgetDrainTask: Task<Void, Error>?

    private weak var context: (any WidgetPurchaseContext)?
    private let dependencies: WidgetPurchaseDependencies

    init(context: any WidgetPurchaseContext, dependencies: WidgetPurchaseDependencies) {
        self.context = context
        self.dependencies = dependencies
    }

    /// Sign-out and account deletion stop a drain that would replay into the next account.
    func cancelDrain() {
        widgetDrainTask?.cancel()
    }
}

// MARK: - Snapshot

extension WidgetPurchaseSync {
    func updateWidgetSnapshot(accentOverride: AppAccentColor? = nil) {
        // Bootstrap reloads run before account state is restored; an empty write here would
        // outlive a process suspended mid-launch and blank the widget.
        guard let context, context.isReady else { return }
        let snapshot = makeWidgetSnapshot(accent: accentOverride ?? context.preferences.accentColor)
        dependencies.widgetStore.save(snapshot: snapshot)
        // The shopping trip reads the same snapshot, so it never disagrees with the widget.
        dependencies.shoppingTrip.sync(with: snapshot)
    }

    /// The active cart as the widgets and the shopping trip draw it; without an account or
    /// cart it is the empty snapshot, whose missing IDs end a running trip.
    func makeWidgetSnapshot(accent activeAccent: AppAccentColor) -> WidgetCartSnapshot {
        guard let context, let accountID = context.account?.id, let familyID = context.activeFamilySpace?.id,
            let list = ShoppingListEntity.primaryList(in: dependencies.cartContent.activeLists)
        else {
            return Self.emptySnapshot(accent: activeAccent)
        }

        let allProducts = dependencies.cartContent.products(inListID: list.id ?? UUID())
        let unpurchased = allProducts.filter { !$0.isPurchasedValue }
        let purchased = allProducts.filter(\.isPurchasedValue)
        let displayProducts: [ProductEntity] =
            Array(unpurchased.prefix(Self.widgetNeededLimit)) + Array(purchased.prefix(Self.widgetCompletedLimit))
        let members = context.familyMembers

        return WidgetCartSnapshot(
            cartTitle: context.cartTitle,
            totalCount: allProducts.count,
            purchasedCount: purchased.count,
            isSyncing: context.isCartSyncing,
            lastUpdated: Date(),
            familyMemberCount: max(1, members.count),
            activePartnerName: Self.partnerName(in: members),
            themeRaw: Self.widgetThemeRaw,
            accentColorRaw: activeAccent.rawValue,
            accountID: accountID,
            familyID: familyID,
            items: displayProducts.compactMap(Self.itemSnapshot(of:))
        )
    }

    private static func emptySnapshot(accent: AppAccentColor) -> WidgetCartSnapshot {
        WidgetCartSnapshot(
            cartTitle: AppSession.defaultFamilyName,
            totalCount: 0,
            purchasedCount: 0,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            activePartnerName: nil,
            themeRaw: widgetThemeRaw,
            accentColorRaw: accent.rawValue,
            items: []
        )
    }

    private static func itemSnapshot(of product: ProductEntity) -> WidgetItemSnapshot? {
        guard let id = product.id else { return nil }
        let isPurchased = product.isPurchasedValue
        let subtitle: String? = {
            if isPurchased, let buyer = product.purchasedByName, !buyer.isEmpty {
                return String(localized: "cart.in_trolley_by \(buyer)")
            }
            if let adder = product.createdByName, !adder.isEmpty {
                return String(localized: "cart.added_by \(adder)")
            }
            return nil
        }()
        return WidgetItemSnapshot(
            id: id,
            name: product.displayName,
            isPurchased: isPurchased,
            categoryRaw: product.categoryValue.rawValue,
            subtitle: subtitle
        )
    }

    private static func partnerName(in members: [FamilyMember]) -> String? {
        guard members.count > 1, let other = members.first(where: { !$0.isCurrentUser }) else { return nil }
        return other.displayName
    }
}

// MARK: - Purchase queue

extension WidgetPurchaseSync {
    func drainWidgetPendingToggles() async {
        do {
            try await applyPendingWidgetPurchases()
        } catch {
            context?.show(error)
        }
    }

    /// Queues the purchase and waits until a drain has saved it. The caller finishes the app's
    /// startup first.
    func performWidgetPurchase(_ request: WidgetPurchaseRequest) async throws {
        guard isAvailable(for: request) else {
            throw WidgetPurchaseError.unavailable
        }
        let widgetStore = dependencies.widgetStore
        try widgetStore.enqueuePurchase(request)
        while try widgetStore.pendingPurchases().contains(where: { $0.id == request.id }) {
            try Task.checkCancellation()
            guard isAvailable(for: request) else {
                throw WidgetPurchaseError.unavailable
            }
            do {
                try await applyPendingWidgetPurchases()
            } catch {
                if try widgetStore.pendingPurchases().contains(where: { $0.id == request.id }) {
                    throw error
                }
            }
        }
        // A check on the Live Activity redraws it when the intent returns, so the trip's
        // queued update must land first (REQ-WIDGET-050).
        await dependencies.shoppingTrip.settle()
    }

    private func isAvailable(for request: WidgetPurchaseRequest) -> Bool {
        isCurrentCart(of: request) && context?.canEdit == true
    }

    private func isCurrentCart(of request: WidgetPurchaseRequest) -> Bool {
        context?.account?.id == request.accountID && context?.activeFamilySpace?.id == request.familyID
    }

    private func applyPendingWidgetPurchases() async throws {
        if let widgetDrainTask {
            try await widgetDrainTask.value
            return
        }
        guard context?.account != nil, context?.activeFamilySpace != nil else { return }
        let task = Task { @MainActor in
            defer {
                widgetDrainTask = nil
                updateWidgetSnapshot()
            }
            try await replayPendingPurchases()
        }
        widgetDrainTask = task
        try await task.value
    }

    private func replayPendingPurchases() async throws {
        var blockedProductIDs = Set<UUID>()
        var firstError: Error?
        for request in try dependencies.widgetStore.pendingPurchases() {
            guard isCurrentCart(of: request) else { continue }
            guard !blockedProductIDs.contains(request.productID) else { continue }
            do {
                try await persistWidgetPurchase(request)
            } catch {
                // Preserve order for this product without blocking unrelated purchases.
                blockedProductIDs.insert(request.productID)
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func persistWidgetPurchase(_ request: WidgetPurchaseRequest) async throws {
        guard isAvailable(for: request) else {
            throw WidgetPurchaseError.unavailable
        }
        let mutations = dependencies.mutations
        mutations.beginCartMutation()
        defer { mutations.finishCartMutation() }
        try await dependencies.cartItems.setPurchased(
            id: request.productID,
            familySpaceID: request.familyID,
            isPurchased: request.isPurchased,
            participantDisplayName: context?.participantName,
            purchasedAt: request.createdAt
        )
        // A crash after save leaves an idempotent desired-state command available for retry.
        try dependencies.widgetStore.acknowledgePurchase(id: request.id)
        if isCurrentCart(of: request) {
            try context?.reload(preferredFamilySpaceID: request.familyID)
            dependencies.cartSync.bumpRevisionAfterLocalChange()
        }
    }
}
