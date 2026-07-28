import CoreData
import Foundation
import OSLog

extension AppSession {
    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async {
        guard let listID = list.id else { return }
        CartSyncLog.action.info("addProduct start name=\(draft.name, privacy: .public)")
        await performMutation(action: "addProduct", successMessage: String(localized: "alert.product_added")) {
            try await self.repository.addProduct(
                to: listID,
                draft: draft,
                purchasedByName: Self.participantName(
                    preferences: self.preferences,
                    account: self.account
                )
            )
        }
    }

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        guard let id = product.id else { return }
        CartSyncLog.action.info("updateProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "updateProduct", successMessage: String(localized: "alert.product_updated")) {
            try await self.repository.updateProduct(id: id, draft: draft)
        }
    }

    func togglePurchased(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        guard canEdit else {
            CartSyncLog.cart.error("togglePurchased denied canEdit=false")
            CartSyncLog.action.error("togglePurchased denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        do {
            CartSyncLog.cart.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            CartSyncLog.action.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            try await repository.togglePurchased(
                id: id,
                participantDisplayName: Self.participantName(
                    preferences: preferences,
                    account: account
                )
            )
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
            let purchasedCount = products.filter(\.isPurchasedValue).count
            let totalCount = products.count
            CartSyncLog.cart.info(
                "togglePurchased done purchased=\(purchasedCount)/\(totalCount)"
            )
            CartSyncLog.action.info("togglePurchased done")
        } catch {
            CartSyncLog.cart.error("togglePurchased failed error=\(error.localizedDescription, privacy: .public)")
            CartSyncLog.action.error(
                "togglePurchased fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        cartContent.products(inListID: listID)
    }

    func deleteProduct(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        CartSyncLog.action.info("deleteProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "deleteProduct", successMessage: String(localized: "alert.product_deleted")) {
            try await self.repository.deleteProduct(id: id)
        }
    }

    func completePurchasedItems(_ list: ShoppingListEntity) async {
        guard let id = list.id else { return }
        CartSyncLog.action.info("completePurchase start list=\(id.uuidString, privacy: .public)")
        await performMutation(
            action: "completePurchase",
            successMessage: String(localized: "alert.purchase_completed")
        ) {
            _ = try await self.repository.completePurchased(listID: id)
        }
    }

    func deleteHistory(_ entry: PurchaseHistoryEntity) async {
        guard let id = entry.id else { return }
        CartSyncLog.action.info("deleteHistory start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "deleteHistory", successMessage: String(localized: "alert.history_deleted")) {
            try await self.repository.deleteHistory(id: id)
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

    private func performMutation(
        action: String,
        successMessage: String?,
        operation: @escaping () async throws -> Void
    ) async {
        _ = successMessage
        guard canEdit else {
            CartSyncLog.action.error("\(action) denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await operation()
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try reload()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.action.info("\(action) done")
        } catch {
            CartSyncLog.action.error(
                "\(action) fail error=\(error.localizedDescription, privacy: .public)"
            )
            show(error)
        }
    }

    private static func participantName(
        preferences: DevicePreferences,
        account: OneCartAccount?
    ) -> String? {
        let trimmed = preferences.participantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return account?.displayName
    }
}
