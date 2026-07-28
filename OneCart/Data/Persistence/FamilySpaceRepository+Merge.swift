import CoreData
import Foundation

extension FamilySpaceRepository {
    func mergeFamilyContent(from sourceID: UUID, into destinationID: UUID) async throws {
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

            for product in source.sortedProducts {
                let copied = ProductEntity(context: context)
                try self.persistence.assign(copied, toSameStoreAs: destination, in: context)
                copied.id = UUID()
                copied.name = product.name
                copied.quantity = product.quantity
                copied.unit = product.unit
                copied.category = product.category
                copied.estimatedPrice = product.estimatedPrice
                copied.originalPrice = product.originalPrice
                copied.loyaltyPrice = product.loyaltyPrice
                copied.note = product.note
                copied.imageURL = product.imageURL
                copied.sourceURL = product.sourceURL
                copied.catalogFetchedAt = product.catalogFetchedAt
                copied.promotionEndsAt = product.promotionEndsAt
                copied.isPurchased = product.isPurchased
                copied.purchasedAt = product.purchasedAt
                copied.purchasedByName = product.purchasedByName
                copied.createdAt = product.createdAt ?? now
                copied.updatedAt = now
                copied.familySpace = destination
                copied.list = targetList
                if let storeID = product.store?.id {
                    copied.store = storeMap[storeID]
                }
            }

            destination.updatedAt = now
            targetList.updatedAt = now
        }
        try await archiveFamilySpace(id: sourceID)
    }

}
