import CoreData
import Foundation
import OSLog

extension AppSession {
    /// Adds a product. Returns the living row ID — a new row, or the existing
    /// row when the normalized name is already on the cart (duplicate
    /// protection). Returns nil when the mutation is denied or fails.
    @discardableResult
    func addProduct(to list: ShoppingListEntity, draft: ProductDraft) async -> UUID? {
        guard let listID = list.id else { return nil }
        let beforeIDs = Set(products(inListID: listID).compactMap(\.id))
        CartSyncLog.action.info("addProduct start name=\(draft.name, privacy: .public)")
        var addedID: UUID?
        let succeeded = await performMutation(
            action: "addProduct",
            successMessage: String(localized: "alert.product_added")
        ) {
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
            let name = draft.name
            Task { await self.refineProductCategory(productID: productID, name: name) }
        }
        return productID
    }

    func updateProduct(_ product: ProductEntity, draft: ProductDraft) async {
        guard let id = product.id, let familyID = product.familySpace?.id else { return }
        CartSyncLog.action.info("updateProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "updateProduct", successMessage: String(localized: "alert.product_updated")) {
            try await self.repository.updateProduct(id: id, familySpaceID: familyID, draft: draft)
        }
        let name = draft.name
        Task { await self.refineProductCategory(productID: id, name: name) }
    }

    private func refineProductCategory(productID: UUID, name: String) async {
        let classified = await ProductCategoryClassifier.shared.classify(name)
        guard canEdit else { return }
        pendingCartMutationCount += 1
        defer { finishCartMutation() }
        guard let product = products.first(where: { $0.id == productID }),
              let familyID = product.familySpace?.id else { return }
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
            try await repository.updateProduct(id: productID, familySpaceID: familyID, draft: draft)
            await persistence.container.viewContext.perform {
                self.persistence.container.viewContext.processPendingChanges()
            }
            try refreshProducts()
            cartSync.bumpRevisionAfterLocalChange()
            CartSyncLog.action.info(
                // swiftlint:disable:next line_length
                "refineProductCategory id=\(productID.uuidString, privacy: .public) category=\(classified.rawValue, privacy: .public)"
            )
        } catch {
            CartSyncLog.action.error(
                "refineProductCategory fail error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func togglePurchased(_ product: ProductEntity) async {
        guard let id = product.id, let familyID = product.familySpace?.id else { return }
        guard canEdit else {
            CartSyncLog.cart.error("togglePurchased denied canEdit=false")
            CartSyncLog.action.error("togglePurchased denied canEdit=false")
            presentAlert(RepositoryError.permissionDenied.localizedDescription)
            return
        }

        pendingCartMutationCount += 1
        defer { finishCartMutation() }
        do {
            CartSyncLog.cart.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            CartSyncLog.action.info("togglePurchased start id=\(id.uuidString, privacy: .public)")
            try await repository.togglePurchased(
                id: id,
                familySpaceID: familyID,
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
            show(error)
        }
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
        guard let id = product.id, let familyID = product.familySpace?.id else { return }
        guard !product.isPurchasedValue else {
            CartSyncLog.action.info("deleteProduct skipped purchased id=\(id.uuidString, privacy: .public)")
            return
        }
        CartSyncLog.action.info("deleteProduct start id=\(id.uuidString, privacy: .public)")
        await performMutation(action: "deleteProduct", successMessage: String(localized: "alert.product_deleted")) {
            try await self.repository.deleteProduct(id: id, familySpaceID: familyID)
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
        pendingCartMutationCount += 1
        defer { finishCartMutation() }
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
                    // swiftlint:disable:next line_length
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
        pendingCartMutationCount += 1
        defer {
            isBusy = false
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
            CartSyncLog.action.info("\(action) done")
            return true
        } catch {
            CartSyncLog.action.error(
                "\(action) fail error=\(error.localizedDescription, privacy: .public)"
            )
            if error as? RepositoryError == .permissionDenied,
               let lastSyncError,
               lastSyncError.localizedCaseInsensitiveContains("production schema")
               || lastSyncError == CloudKitUserFacingError.productionSchemaMissing
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
            try? await household.reconcileProvisionalPersonalCartIfNeeded(for: account)
        }
    }

    static func participantName(
        preferences: DevicePreferences,
        account: OneCartAccount?
    ) -> String? {
        ParticipantDisplayName.resolved(preferences: preferences, account: account)
    }

    func updateParticipantDisplayName(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRetitlePersonalCart = personalCartStillFollowsParticipantName()
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
        if shouldRetitlePersonalCart {
            await syncPersonalCartNameWithParticipant()
        }
    }

    private func personalCartStillFollowsParticipantName() -> Bool {
        guard let account else { return false }
        guard let personal = personalFamilySpace(for: account) else { return false }
        return personal.displayName == Self.householdCartName(for: account)
    }

    private func personalFamilySpace(for account: OneCartAccount) -> FamilySpace? {
        let spaces = (try? repository.fetchFamilySpaces(for: account.id)) ?? []
        let personalSpaces = spaces.filter {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
        let preferredID = activeFamilySpace.flatMap { family in
            persistence.scope(for: family) == .private ? family.id : nil
        } ?? household.restoredPersonalFamilyID(accountID: account.id)
        return personalSpaces.first(where: { $0.id == preferredID })
            ?? personalSpaces.first(where: \.isHouseholdDefaultValue) ?? personalSpaces.first
    }

    private func syncPersonalCartNameWithParticipant() async {
        guard let account,
              let personal = personalFamilySpace(for: account),
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
