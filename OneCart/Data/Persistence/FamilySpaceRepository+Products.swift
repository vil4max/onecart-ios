import CoreData
import Foundation

extension FamilySpaceRepository {
    /// Adds a new cart line item. Same name / catalog URL as an existing row still
    /// creates a separate unique position — quantities are never summed across members.
    @discardableResult
    func addProduct(
        to listID: UUID,
        id: UUID = UUID(),
        draft: ProductDraft,
        createdByName: String? = nil
    ) async throws -> UUID {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }

        return try await persistence.performBackgroundTask { context in
            guard let list = try Self.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            try self.requireUpdatePermission(for: list)
            guard let space = list.familySpace else {
                throw RepositoryError.familySpaceNotFound
            }

            // Idempotent only for the exact stable id (CloudKit redelivery), never by name.
            if let existing = try Self.fetchProduct(
                id: id,
                familySpaceID: space.id,
                in: context
            ) {
                return existing.id ?? id
            }

            let now = Date()
            let product = ProductEntity(context: context)
            try self.persistence.assign(product, toSameStoreAs: list, in: context)
            product.id = id
            Self.apply(draft: draft, to: product)
            product.isPurchased = false
            product.createdAt = now
            product.updatedAt = now
            product.purchasedAt = nil
            product.purchasedByName = nil
            product.createdByName = createdByName?.trimmedNilIfEmpty
            product.familySpace = space
            product.list = list
            product.store = list.store
            list.updatedAt = now
            space.updatedAt = now
            return id
        }
    }

    func updateProduct(id: UUID, draft: ProductDraft) async throws {
        let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw RepositoryError.invalidName }

        try await persistence.performBackgroundTask { context in
            guard let product = try Self.fetchProduct(id: id, in: context) else {
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            let now = Date()
            Self.apply(draft: draft, to: product)
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    func togglePurchased(
        id: UUID,
        participantDisplayName: String?
    ) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try Self.fetchProduct(id: id, in: context) else {
                throw RepositoryError.productNotFound
            }
            try self.requireUpdatePermission(for: product)
            let now = Date()
            let nextValue = !product.isPurchasedValue
            product.isPurchased = NSNumber(value: nextValue)
            product.purchasedAt = nextValue ? now : nil
            product.purchasedByName = nextValue
                ? participantDisplayName?.trimmedNilIfEmpty
                : nil
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    func deleteProduct(id: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try Self.fetchProduct(id: id, in: context) else {
                throw RepositoryError.productNotFound
            }
            try self.requireDeletePermission(for: product)
            guard !product.isPurchasedValue else { return }
            let now = Date()
            product.deletedAt = now
            product.updatedAt = now
            product.list?.updatedAt = now
            product.familySpace?.updatedAt = now
        }
    }

    @discardableResult
    func completePurchased(listID: UUID) async throws -> UUID? {
        try await archivePurchased(listID: listID, purchasedBefore: nil)
    }

    @discardableResult
    func archivePurchasedBefore(listID: UUID, cutoff: Date) async throws -> UUID? {
        try await archivePurchased(listID: listID, purchasedBefore: cutoff)
    }

    @discardableResult
    private func archivePurchased(listID: UUID, purchasedBefore cutoff: Date?) async throws -> UUID? {
        try await persistence.performBackgroundTask { context in
            guard let list = try Self.fetchList(id: listID, in: context) else {
                throw RepositoryError.listNotFound
            }
            try self.requireUpdatePermission(for: list)
            guard let space = list.familySpace else {
                throw RepositoryError.familySpaceNotFound
            }

            let purchased = list.sortedProducts.filter { product in
                guard product.isPurchasedValue else { return false }
                guard let cutoff else { return true }
                let purchasedAt = product.purchasedAt ?? product.updatedAt ?? .distantPast
                return purchasedAt < cutoff
            }
            guard !purchased.isEmpty else { return nil }

            let now = Date()
            let historyID = UUID()
            let history = PurchaseHistoryEntity(context: context)
            try self.persistence.assign(history, toSameStoreAs: list, in: context)
            history.id = historyID
            history.total = NSNumber(
                value: purchased.reduce(0) { $0 + $1.estimatedPriceValue }
            )
            history.date = now
            history.createdAt = now
            history.updatedAt = now
            history.familySpace = space
            history.store = list.store

            let names = Set(
                purchased.compactMap { $0.purchasedByName?.trimmedNilIfEmpty }
            ).sorted()
            history.memberNames = names.isEmpty ? String(localized: "common.default_group") : names
                .joined(separator: ", ")

            for product in purchased {
                let item = HistoryItemEntity(context: context)
                try self.persistence.assign(item, toSameStoreAs: list, in: context)
                item.id = product.id ?? UUID()
                item.name = product.name
                item.quantity = product.quantity
                item.unit = product.unit
                item.category = product.category
                item.estimatedPrice = product.estimatedPrice
                item.originalPrice = product.originalPrice
                item.imageURL = product.imageURL
                item.sourceURL = product.sourceURL
                item.note = product.note
                item.purchasedAt = product.purchasedAt ?? now
                item.purchasedByName = product.purchasedByName
                item.storeName = product.store?.name
                item.createdAt = product.createdAt
                item.updatedAt = now
                item.familySpace = space
                item.history = history
                product.deletedAt = now
                product.updatedAt = now
            }

            list.updatedAt = now
            space.updatedAt = now
            return historyID
        }
    }

    static func apply(draft: ProductDraft, to product: ProductEntity) {
        product.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        product.quantity = NSNumber(value: max(draft.quantity, 0.001))
        product.unit = draft.unit.rawValue
        product.category = draft.category.rawValue
        product.estimatedPrice = NSNumber(value: max(draft.estimatedPrice, 0))
        product.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        product.imageURL = draft.imageURL?.trimmedNilIfEmpty
        product.sourceURL = draft.sourceURL?.trimmedNilIfEmpty
        product.originalPrice = draft.originalPrice.map { NSNumber(value: max($0, 0)) }
        product.loyaltyPrice = draft.loyaltyPrice.map { NSNumber(value: max($0, 0)) }
        product.catalogFetchedAt = draft.catalogFetchedAt
        product.promotionEndsAt = draft.promotionEndsAt
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
