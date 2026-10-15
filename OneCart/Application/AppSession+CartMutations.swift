import CoreData
import Foundation
import OSLog
import SwiftUI
import UIKit

extension AppSession {
    /// Adds a product. Returns the living row ID — a new row, or the existing
    /// row when the normalized name is already on the cart (duplicate
    /// protection). Returns nil when the mutation is denied or fails.
    @discardableResult
    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async -> UUID? {
        guard let listID = list.id else { return nil }
        let beforeIDs = Set(products(inListID: listID).compactMap(\.id))
        CartSyncLog.action.info("addProduct start")
        var addedID: UUID?
        let succeeded = await performMutation(action: "addProduct") {
            addedID = try await self.repository.addProduct(
                to: listID,
                draft: draft,
                createdByName: Self.participantName(
                    preferences: self.preferences,
                    account: self.account
                )
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

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        guard let id = product.id, let familyID = product.familySpace?.id else {
            logStaleProduct(action: "updateProduct")
            return
        }
        CartSyncLog.action.info("updateProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "updateProduct") {
            try await self.repository.updateProduct(id: id, familySpaceID: familyID, draft: draft)
        }
        scheduleCategoryRefinement(productID: id, name: draft.name)
    }

    /// A newer edit of the same row supersedes any refinement still classifying its old name.
    private func scheduleCategoryRefinement(productID: UUID, name: String) {
        categoryRefinementTasks[productID]?.cancel()
        categoryRefinementTasks[productID] = Task {
            await self.refineProductCategory(productID: productID, name: name)
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
        let classified = await categoryClassifier.classify(name)
        guard !Task.isCancelled, canEdit else { return }
        pendingCartMutationCount += 1
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
            try await repository.updateProductCategory(id: productID, familySpaceID: familyID, category: classified)
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
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

    /// Flips the row as the caller holds it; for callers without a rendered row state.
    func togglePurchased(_ product: ProductEntity) async {
        await setPurchased(product, isPurchased: !product.isPurchasedValue)
    }

    func setPurchased(_ product: ProductEntity, isPurchased: Bool) async {
        guard let id = product.id, let familyID = product.familySpace?.id else {
            logStaleProduct(action: "togglePurchased")
            return
        }
        guard canEdit else {
            CartSyncLog.cart.error("togglePurchased denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        pendingCartMutationCount += 1
        defer { finishCartMutation() }
        do {
            CartSyncLog.cart.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            try await repository.setPurchasedState(
                id: id,
                familySpaceID: familyID,
                isPurchased: isPurchased,
                participantDisplayName: Self.participantName(
                    preferences: preferences,
                    account: account
                )
            )
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            let toggleAnimation: Animation? =
                UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.38, dampingFraction: 0.82)
            withAnimation(toggleAnimation) {
                do {
                    try refreshProducts()
                    cartSync.bumpRevisionAfterLocalChange()
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
            CartHaptics.light()
        } catch {
            CartSyncLog.cart.error("togglePurchased failed error=\(error.localizedDescription, privacy: .public)")
            show(error)
        }
    }

    /// A hard refresh resets the view context, so a row captured by an in-flight tap loses its
    /// identifiers. The tap is dropped; the log keeps that visible in diagnostics.
    private func logStaleProduct(action: String) {
        CartSyncLog.action.error("\(action, privacy: .public) dropped staleProduct=true")
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        cartContent.products(inListID: listID)
    }

    /// Merges same-name rows that arrived via CloudKit with different stable
    /// IDs. No-op when there is nothing to merge or editing is unavailable.
    func deduplicateCartIfNeeded() async {
        guard canEdit else { return }
        do {
            let merged = try await repository.deduplicateProductsByName()
            guard merged > 0 else { return }
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try reload()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.action.info("deduplicateCart merged=\(merged)")
        } catch {
            CartSyncLog.action.error(
                "deduplicateCart fail error=\(error.localizedDescription, privacy: .public)"
            )
        }
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
        await performMutation(action: "deleteProduct") {
            try await self.repository.deleteProduct(id: id, familySpaceID: familyID)
        }
    }

    func completePurchasedItems(_ list: ShoppingListEntity) async {
        guard let id = list.id else { return }
        CartSyncLog.action.info("completePurchase start list=\(id.uuidString, privacy: .public)")
        await performMutation(action: "completePurchase") {
            _ = try await self.repository.completePurchased(listID: id)
        }
    }

    func archiveStalePurchasedIfNeeded(
        calendar: Calendar = .current
    ) async {
        guard canEdit else { return }
        pendingCartMutationCount += 1
        defer { finishCartMutation() }
        let cutoff = calendar.startOfDay(for: clock.now())
        var didArchive = false

        for list in activeLists {
            guard let id = list.id else { continue }
            do {
                if try await repository.archivePurchasedBefore(listID: id, cutoff: cutoff) != nil {
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
        await persistence.container.viewContext.perform {
            self.persistence.container.viewContext.processPendingChanges()
        }
        do {
            try reload()
            cartSync.bumpRevisionAfterLocalChange()
        } catch {
            show(error)
        }
    }

    func loadMoreHistory() {
        guard let familySpaceID = activeFamilySpace?.id else { return }
        do {
            try cartContent.loadMoreHistory(familySpaceID: familySpaceID)
        } catch {
            show(error)
        }
    }

    @discardableResult
    private func performMutation(
        action: String,
        operation: @escaping () async throws -> Void
    ) async -> Bool {
        guard canEdit else {
            CartSyncLog.action.error("\(action, privacy: .public) denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return false
        }

        beginBusyOperation()
        pendingCartMutationCount += 1
        defer {
            endBusyOperation()
            finishCartMutation()
        }

        do {
            try await operation()
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try reload()
            cartSync.bumpRevisionAfterLocalChange()
            CartHaptics.success()
            CartSyncLog.action.info("\(action, privacy: .public) done")
            return true
        } catch {
            CartSyncLog.action.error(
                "\(action, privacy: .public) fail error=\(error.localizedDescription, privacy: .public)"
            )
            guard !CartIntentContext.isActive else { return false }
            if error as? RepositoryError == .permissionDenied,
                lastSyncError == CloudKitUserFacingError.productionSchemaMissing
            {
                presentProductionSchemaAlertIfNeeded(CloudKitUserFacingError.productionSchemaMissing)
                return false
            }
            show(error)
            return false
        }
    }

    func finishCartMutation() {
        pendingCartMutationCount -= 1
        guard pendingCartMutationCount == 0, let account else { return }
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
}
