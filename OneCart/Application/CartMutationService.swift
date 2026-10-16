import CoreData
import Foundation
import OSLog
import SwiftUI
import UIKit

struct CartMutationDependencies {
    let persistence: PersistenceController
    let cartItems: any CartItemsRepository
    let purchaseArchiver: any PurchaseArchiver
    let deduplicator: any CartDeduplicator
    let categoryClassifier: any CategoryClassifying
    let cartContent: CartContentStore
    let cartSync: CartSyncService
    let household: HouseholdCartCoordinator
    let clock: AppClock
}

/// Adds, renames, checks, deletes and archives cart lines, and refines a new line's category.
/// Owns the count of mutations in flight, which defers the personal-cart reconciliation, and
/// the category refinements still classifying.
@MainActor
final class CartMutationService {
    private(set) var pendingCartMutationCount = 0
    /// In-flight category refinements by product ID; a rename cancels the refinement of the
    /// old name so it can never write over the new one.
    private(set) var categoryRefinementTasks: [UUID: Task<Void, Never>] = [:]

    private weak var context: (any CartMutationContext)?
    private let dependencies: CartMutationDependencies

    init(context: any CartMutationContext, dependencies: CartMutationDependencies) {
        self.context = context
        self.dependencies = dependencies
    }

    private var canEdit: Bool {
        context?.canEdit ?? false
    }

    private var products: [ProductEntity] {
        dependencies.cartContent.products
    }
}

// MARK: - Add, rename, delete

extension CartMutationService {
    /// Adds a product. Returns the living row ID — a new row, or the existing
    /// row when the normalized name is already on the cart (duplicate
    /// protection). Returns nil when the mutation is denied or fails.
    @discardableResult
    func addProduct(toListID listID: UUID, draft: ProductDraft) async -> UUID? {
        let beforeIDs = Set(dependencies.cartContent.products(inListID: listID).compactMap(\.id))
        CartSyncLog.action.info("addProduct start")
        var addedID: UUID?
        let cartItems = dependencies.cartItems
        let author = context?.cartAuthor ?? CartAuthor(displayName: nil)
        let succeeded = await performMutation(action: "addProduct") {
            addedID = try await cartItems.addProduct(
                to: listID,
                id: UUID(),
                draft: draft,
                author: author
            )
        }
        guard succeeded, let productID = addedID else { return nil }
        // Only refine category for genuinely new rows — a duplicate reuses
        // the existing row untouched so family edits are never overwritten.
        if !beforeIDs.contains(productID) {
            scheduleCategoryRefinement(productID: productID, name: draft.name)
        }
        return productID
    }

    func updateProduct(id: UUID, draft: ProductDraft) async {
        guard let product = liveProduct(id: id) else {
            logStaleProduct(action: "updateProduct")
            return
        }
        await updateProduct(product, draft: draft)
    }

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        guard let id = product.id, let familyID = product.familySpace?.id else {
            logStaleProduct(action: "updateProduct")
            return
        }
        CartSyncLog.action.info("updateProduct start id=\(id.uuidString, privacy: .public)")
        let cartItems = dependencies.cartItems
        await performMutation(action: "updateProduct") {
            try await cartItems.updateProduct(id: id, familySpaceID: familyID, draft: draft)
        }
        scheduleCategoryRefinement(productID: id, name: draft.name)
    }

    func deleteProduct(id: UUID) async {
        guard let product = liveProduct(id: id) else {
            logStaleProduct(action: "deleteProduct")
            return
        }
        await deleteProduct(product)
    }

    func deleteProduct(_ product: ProductEntity) async {
        guard let id = product.id, let familyID = product.familySpace?.id else {
            logStaleProduct(action: "deleteProduct")
            return
        }
        guard !product.isPurchasedValue else {
            CartSyncLog.action.info("deleteProduct skipped purchased id=\(id.uuidString, privacy: .public)")
            return
        }
        CartSyncLog.action.info("deleteProduct start id=\(id.uuidString, privacy: .public)")
        cancelCategoryRefinement(productID: id)
        let cartItems = dependencies.cartItems
        await performMutation(action: "deleteProduct") {
            try await cartItems.deleteProduct(id: id, familySpaceID: familyID)
        }
    }

    /// A hard refresh resets the view context, so a row captured by an in-flight tap loses its
    /// identifiers, and a screen's ID can outlive its row. The tap is dropped; the log keeps that
    /// visible in diagnostics.
    private func logStaleProduct(action: String) {
        CartSyncLog.action.error("\(action, privacy: .public) dropped staleProduct=true")
    }

    /// The live row behind an ID a screen holds; nil once a reload no longer has it.
    private func liveProduct(id: UUID) -> ProductEntity? {
        products.first { $0.id == id }
    }
}

// MARK: - Category refinement

extension CartMutationService {
    /// A newer edit of the same row supersedes any refinement still classifying its old name.
    private func scheduleCategoryRefinement(productID: UUID, name: String) {
        categoryRefinementTasks[productID]?.cancel()
        // The task keeps the session alive while it runs, as it did when the session ran it.
        let context = context
        categoryRefinementTasks[productID] = Task {
            await self.refineProductCategory(productID: productID, name: name)
            withExtendedLifetime(context) {}
            // A superseded refinement was cancelled before its successor took the slot, so an
            // uncancelled one still owns it.
            if !Task.isCancelled {
                self.categoryRefinementTasks.removeValue(forKey: productID)
            }
        }
    }

    func cancelCategoryRefinement(productID: UUID) {
        categoryRefinementTasks.removeValue(forKey: productID)?.cancel()
    }

    func cancelAllCategoryRefinements() {
        categoryRefinementTasks.values.forEach { $0.cancel() }
        categoryRefinementTasks.removeAll()
    }

    private func refineProductCategory(productID: UUID, name: String) async {
        let classified = await dependencies.categoryClassifier.classify(name)
        guard !Task.isCancelled, canEdit else { return }
        beginCartMutation()
        defer { finishCartMutation() }
        guard let product = products.first(where: { $0.id == productID }),
            let familyID = product.familySpace?.id
        else { return }
        // The row may have been renamed while the classifier ran; its new name gets its own
        // refinement, and this one must not label it with the old name's category.
        let normalized = FamilyCartMerge.normalizedProductName
        guard normalized(product.displayName) == normalized(name) else { return }
        guard product.categoryValue != classified else { return }

        do {
            try await dependencies.cartItems.updateProductCategory(
                id: productID,
                familySpaceID: familyID,
                category: classified
            )
            await processPendingViewContextChanges()
            try context?.refreshProducts()
            dependencies.cartSync.bumpRevisionAfterLocalChange()
            let id = productID.uuidString
            let category = classified.rawValue
            CartSyncLog.action.info(
                "refineProductCategory id=\(id, privacy: .public) category=\(category, privacy: .public)"
            )
        } catch {
            CartSyncLog.action.error(
                "refineProductCategory fail error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

// MARK: - Purchase state

extension CartMutationService {
    func setPurchased(productID: UUID, isPurchased: Bool) async {
        guard let product = liveProduct(id: productID) else {
            logStaleProduct(action: "togglePurchased")
            return
        }
        await setPurchased(product, isPurchased: isPurchased)
    }

    func setPurchased(_ product: ProductEntity, isPurchased: Bool) async {
        guard let id = product.id, let familyID = product.familySpace?.id else {
            logStaleProduct(action: "togglePurchased")
            return
        }
        guard canEdit else {
            CartSyncLog.cart.error("togglePurchased denied canEdit=false")
            context?.presentAlert(RepositoryError.permissionDenied.localizedDescription, kind: .error, playHaptic: true)
            return
        }

        beginCartMutation()
        defer { finishCartMutation() }
        do {
            CartSyncLog.cart.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            try await dependencies.cartItems.setPurchasedState(
                id: id,
                familySpaceID: familyID,
                isPurchased: isPurchased,
                author: context?.cartAuthor ?? CartAuthor(displayName: nil)
            )
            await processPendingViewContextChanges()
            refreshAfterPurchaseChange()
            CartHaptics.light()
        } catch {
            CartSyncLog.cart.error("togglePurchased failed error=\(error.localizedDescription, privacy: .public)")
            context?.show(error)
        }
    }

    private func refreshAfterPurchaseChange() {
        let toggleAnimation: Animation? =
            UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.38, dampingFraction: 0.82)
        withAnimation(toggleAnimation) {
            do {
                try context?.refreshProducts()
                dependencies.cartSync.bumpRevisionAfterLocalChange()
            } catch {
                CartSyncLog.cart.error(
                    "togglePurchased refresh error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        let purchasedCount = products.filter(\.isPurchasedValue).count
        let totalCount = products.count
        CartSyncLog.cart.info(
            "togglePurchased done purchased=\(purchasedCount)/\(totalCount)"
        )
    }
}

// MARK: - Merge and archive

extension CartMutationService {
    /// Merges same-name rows that arrived via CloudKit with different stable
    /// IDs. No-op when there is nothing to merge or editing is unavailable.
    func deduplicateCartIfNeeded() async {
        guard canEdit else { return }
        do {
            let merged = try await dependencies.deduplicator.deduplicateProductsByName()
            guard merged > 0 else { return }
            await processPendingViewContextChanges()
            try context?.reload(preferredFamilySpaceID: nil)
            dependencies.cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.action.info("deduplicateCart merged=\(merged)")
        } catch {
            CartSyncLog.action.error(
                "deduplicateCart fail error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func completePurchasedItems(_ list: ShoppingListEntity) async {
        guard let id = list.id else { return }
        CartSyncLog.action.info("completePurchase start list=\(id.uuidString, privacy: .public)")
        let purchaseArchiver = dependencies.purchaseArchiver
        await performMutation(action: "completePurchase") {
            _ = try await purchaseArchiver.completePurchased(listID: id)
        }
    }

    func archiveStalePurchasedIfNeeded(calendar: Calendar = .current) async {
        guard canEdit else { return }
        beginCartMutation()
        defer { finishCartMutation() }
        let cutoff = calendar.startOfDay(for: dependencies.clock.now())
        var didArchive = false

        for list in dependencies.cartContent.activeLists {
            guard let id = list.id else { continue }
            do {
                if try await dependencies.purchaseArchiver.archivePurchasedBefore(listID: id, cutoff: cutoff) != nil {
                    didArchive = true
                    CartSyncLog.action.info(
                        "archiveStalePurchased list=\(id.uuidString, privacy: .public)"
                    )
                }
            } catch {
                let listID = id.uuidString
                let message = error.localizedDescription
                CartSyncLog.action.error(
                    "archiveStalePurchased fail list=\(listID, privacy: .public) error=\(message, privacy: .public)"
                )
            }
        }

        guard didArchive else { return }
        await processPendingViewContextChanges()
        do {
            try context?.reload(preferredFamilySpaceID: nil)
            dependencies.cartSync.bumpRevisionAfterLocalChange()
        } catch {
            context?.show(error)
        }
    }
}

// MARK: - Mutation bookkeeping

extension CartMutationService {
    /// Counts a write in flight; the personal-cart reconciliation waits until none are left.
    func beginCartMutation() {
        pendingCartMutationCount += 1
    }

    func finishCartMutation() {
        pendingCartMutationCount -= 1
        guard pendingCartMutationCount == 0, let account = context?.account else { return }
        let household = dependencies.household
        Task { @MainActor in
            do {
                try await household.reconcileProvisionalPersonalCartIfNeeded(for: account)
            } catch {
                CartSyncLog.cart.error(
                    "reconcileProvisionalPersonalCart fail error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    @discardableResult
    private func performMutation(
        action: String,
        operation: @escaping () async throws -> Void
    ) async -> Bool {
        guard let context, context.canEdit else {
            CartSyncLog.action.error("\(action, privacy: .public) denied canEdit=false")
            context?.presentAlert(RepositoryError.permissionDenied.localizedDescription, kind: .error, playHaptic: true)
            return false
        }

        context.beginBusyOperation()
        beginCartMutation()
        defer {
            context.endBusyOperation()
            finishCartMutation()
        }

        do {
            try await operation()
            await processPendingViewContextChanges()
            try context.reload(preferredFamilySpaceID: nil)
            dependencies.cartSync.bumpRevisionAfterLocalChange()
            CartHaptics.success()
            CartSyncLog.action.info("\(action, privacy: .public) done")
            return true
        } catch {
            CartSyncLog.action.error(
                "\(action, privacy: .public) fail error=\(error.localizedDescription, privacy: .public)"
            )
            guard !CartIntentContext.isActive else { return false }
            if error as? RepositoryError == .permissionDenied,
                context.lastSyncError == CloudKitUserFacingError.productionSchemaMissing
            {
                context.presentProductionSchemaAlertIfNeeded(CloudKitUserFacingError.productionSchemaMissing)
                return false
            }
            context.show(error)
            return false
        }
    }

    private func processPendingViewContextChanges() async {
        let viewContext = dependencies.persistence.container.viewContext
        await viewContext.perform {
            viewContext.processPendingChanges()
        }
    }
}
