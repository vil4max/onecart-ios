import CoreData
import Foundation
import OSLog

extension AppSession {
    @discardableResult
    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async -> Bool {
        guard let listID = list.id else { return false }
        let beforeIDs = Set(products(inListID: listID).compactMap(\.id))
        CartSyncLog.action.info("addProduct start name=\(draft.name, privacy: .public)")
        let succeeded = await performMutation(
            action: "addProduct",
            successMessage: String(localized: "alert.product_added")
        ) {
            try await self.repository.addProduct(
                to: listID,
                draft: draft,
                createdByName: Self.participantName(
                    preferences: self.preferences,
                    account: self.account
                )
            )
        }
        guard succeeded else { return false }
        let addedIDs = Set(products(inListID: listID).compactMap(\.id)).subtracting(beforeIDs)
        if let productID = addedIDs.first {
            let name = draft.name
            Task { await self.refineProductCategory(productID: productID, name: name) }
        }
        return true
    }

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        guard let id = product.id else { return }
        CartSyncLog.action.info("updateProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "updateProduct", successMessage: String(localized: "alert.product_updated")) {
            try await self.repository.updateProduct(id: id, draft: draft)
        }
        let name = draft.name
        Task { await self.refineProductCategory(productID: id, name: name) }
    }

    private func refineProductCategory(productID: UUID, name: String) async {
        let classified = await ProductCategoryClassifier.shared.classify(name)
        guard let product = products.first(where: { $0.id == productID }) else { return }
        guard product.categoryValue != classified else { return }

        let draft = ProductDraft(
            name: product.displayName,
            quantity: product.quantityValue,
            unit: product.unitValue,
            category: classified,
            estimatedPrice: product.estimatedPriceValue,
            note: product.noteValue,
            imageURL: product.imageURL,
            sourceURL: product.sourceURL,
            originalPrice: product.originalPrice?.doubleValue,
            loyaltyPrice: product.loyaltyPrice?.doubleValue,
            catalogFetchedAt: product.catalogFetchedAt,
            promotionEndsAt: product.promotionEndsAt
        )

        do {
            try await repository.updateProduct(id: productID, draft: draft)
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.action.info(
                "refineProductCategory id=\(productID.uuidString, privacy: .public) category=\(classified.rawValue, privacy: .public)"
            )
        } catch {
            CartSyncLog.action.error(
                "refineProductCategory fail error=\(error.localizedDescription, privacy: .public)"
            )
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
            CartHaptics.light()
        } catch {
            CartSyncLog.cart.error("togglePurchased failed error=\(error.localizedDescription, privacy: .public)")
            CartSyncLog.action.error(
                "togglePurchased fail error=\(error.localizedDescription, privacy: .public)"
            )
            CartHaptics.error()
            show(error)
        }
    }

    func products(inListID listID: UUID) -> [ProductEntity] {
        cartContent.products(inListID: listID)
    }

    func deleteProduct(_ product: ProductEntity) async {
        guard let id = product.id else { return }
        guard !product.isPurchasedValue else {
            CartSyncLog.action.info("deleteProduct skipped purchased id=\(id.uuidString, privacy: .public)")
            return
        }
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

    func archiveStalePurchasedIfNeeded(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard canEdit else { return }
        let cutoff = calendar.startOfDay(for: now)
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
                CartSyncLog.action.error(
                    "archiveStalePurchased fail list=\(id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
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
        successMessage: String?,
        operation: @escaping () async throws -> Void
    ) async -> Bool {
        _ = successMessage
        guard canEdit else {
            CartSyncLog.action.error("\(action) denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return false
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
            CartHaptics.success()
            CartSyncLog.action.info("\(action) done")
            return true
        } catch {
            CartSyncLog.action.error(
                "\(action) fail error=\(error.localizedDescription, privacy: .public)"
            )
            CartHaptics.error()
            show(error)
            return false
        }
    }

    private static func participantName(
        preferences: DevicePreferences,
        account: OneCartAccount?
    ) -> String? {
        ParticipantDisplayName.resolved(preferences: preferences, account: account)
    }

    func updateParticipantDisplayName(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ParticipantDisplayName.isPlaceholder(trimmed) {
            preferences.participantDisplayName = ""
            if let account {
                self.account = OneCartAccount(
                    id: account.id,
                    displayName: ParticipantDisplayName.placeholder,
                    avatarURL: account.avatarURL,
                    bannerURL: account.bannerURL
                )
            }
        } else {
            preferences.participantDisplayName = trimmed
            if let account {
                self.account = OneCartAccount(
                    id: account.id,
                    displayName: trimmed,
                    avatarURL: account.avatarURL,
                    bannerURL: account.bannerURL
                )
            }
            if let index = familyMembers.firstIndex(where: \.isCurrentUser) {
                let member = familyMembers[index]
                familyMembers[index] = FamilyMember(
                    id: member.id,
                    displayName: trimmed,
                    access: member.access,
                    joinedAt: member.joinedAt,
                    isCurrentUser: true,
                    avatarURL: member.avatarURL,
                    bannerURL: member.bannerURL
                )
            }
        }
        await syncPersonalCartNameWithParticipant()
    }

    private func syncPersonalCartNameWithParticipant() async {
        guard let account else { return }
        let personalSpaces = familySpaces.filter {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
        guard let personal = personalSpaces.first(where: \.isHouseholdDefaultValue)
            ?? personalSpaces.first,
            let familyID = personal.id
        else { return }

        let newName = Self.householdCartName(for: account)
        guard personal.displayName != newName else { return }

        do {
            try await repository.renameFamilySpace(id: familyID, name: newName)
            try reload(preferredFamilySpaceID: activeFamilySpace?.id ?? familyID)
            if activeFamilySpace?.id == familyID {
                clearPreparedInviteLink()
                scheduleInviteLinkPreparation()
            }
        } catch {
            show(error)
        }
    }
}
