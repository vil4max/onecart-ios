import CoreData
import Foundation

extension FamilySpaceRepository {
    func mergeFamilyContent(
        from sourceID: UUID,
        into destinationID: UUID,
        archiveSource: Bool = true
    ) async throws {
        try await persistence.performBackgroundTask(author: "OneCartFamilyMerge") { context in
            let source = try Self.requireFamilySpace(id: sourceID, in: context)
            let destination = try Self.requireFamilySpace(id: destinationID, in: context)
            guard self.persistence.scope(for: source.objectID) == .private else {
                throw RepositoryError.crossShareRelationship
            }
            try self.requireUpdatePermission(for: destination)

            let destinationList = destination.activeLists.first
                ?? destination.sortedLists.first
            guard let targetList = destinationList, targetList.id != nil else {
                throw RepositoryError.listNotFound
            }

            var storeMap: [UUID: StoreEntity] = [:]
            for store in destination.sortedStores {
                if let storeID = store.id {
                    storeMap[storeID] = store
                }
            }

            let now = Date()
            for store in source.sortedStores {
                let copied = StoreEntity(context: context)
                try self.persistence.assign(copied, toSameStoreAs: destination, in: context)
                let newStoreID = UUID()
                copied.id = newStoreID
                copied.name = store.name
                copied.icon = store.icon
                copied.colorHex = store.colorHex
                copied.address = store.address
                copied.latitude = store.latitude
                copied.longitude = store.longitude
                copied.externalAppURL = store.externalAppURL
                copied.isPinned = store.isPinned
                copied.createdAt = store.createdAt ?? now
                copied.updatedAt = now
                copied.familySpace = destination
                if let sourceStoreID = store.id {
                    storeMap[sourceStoreID] = copied
                }
            }

            var destinationByName: [String: ProductEntity] = [:]
            for product in destination.sortedProducts {
                let key = FamilyCartMerge.normalizedProductName(product.displayName)
                guard !key.isEmpty else { continue }
                if let existing = destinationByName[key] {
                    let preferNew = FamilyCartMerge.shouldPreferSourceProduct(
                        sourceUpdatedAt: product.updatedAt,
                        destinationUpdatedAt: existing.updatedAt
                    )
                    if preferNew {
                        destinationByName[key] = product
                    }
                } else {
                    destinationByName[key] = product
                }
            }

            for product in source.sortedProducts {
                let key = FamilyCartMerge.normalizedProductName(product.displayName)
                if let existing = destinationByName[key],
                   FamilyCartMerge.shouldPreferSourceProduct(
                       sourceUpdatedAt: product.updatedAt,
                       destinationUpdatedAt: existing.updatedAt
                   )
                {
                    Self.applyProductFields(from: product, onto: existing, now: now)
                    if let storeID = product.store?.id {
                        existing.store = storeMap[storeID]
                    }
                    existing.list = targetList
                    existing.updatedAt = product.updatedAt ?? now
                    continue
                }

                if destinationByName[key] != nil {
                    continue
                }

                let copied = ProductEntity(context: context)
                try self.persistence.assign(copied, toSameStoreAs: destination, in: context)
                copied.id = UUID()
                Self.applyProductFields(from: product, onto: copied, now: now)
                copied.createdAt = product.createdAt ?? now
                copied.updatedAt = product.updatedAt ?? now
                copied.familySpace = destination
                copied.list = targetList
                if let storeID = product.store?.id {
                    copied.store = storeMap[storeID]
                }
                if !key.isEmpty {
                    destinationByName[key] = copied
                }
            }

            destination.updatedAt = now
            targetList.updatedAt = now
        }
        if archiveSource {
            try await archiveFamilySpace(id: sourceID)
        }
    }

    private static func applyProductFields(
        from source: ProductEntity,
        onto destination: ProductEntity,
        now: Date
    ) {
        destination.name = source.name
        destination.quantity = source.quantity
        destination.unit = source.unit
        destination.category = source.category
        destination.estimatedPrice = source.estimatedPrice
        destination.originalPrice = source.originalPrice
        destination.loyaltyPrice = source.loyaltyPrice
        destination.note = source.note
        destination.imageURL = source.imageURL
        destination.sourceURL = source.sourceURL
        destination.catalogFetchedAt = source.catalogFetchedAt
        destination.promotionEndsAt = source.promotionEndsAt
        destination.isPurchased = source.isPurchased
        destination.purchasedAt = source.purchasedAt
        destination.purchasedByName = source.purchasedByName
        destination.createdByName = source.createdByName
        if destination.createdAt == nil {
            destination.createdAt = source.createdAt ?? now
        }
    }
}
