import CoreData
import Foundation

struct LocalFamilyMetadata: Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let role: String?
    let needsRemoteCreation: Bool
}

@MainActor
final class FamilySyncService {
    private let persistence: PersistenceController
    private let repository: FamilySpaceRepository
    private let backend: SupabaseBackendService

    init(
        persistence: PersistenceController,
        repository: FamilySpaceRepository,
        backend: SupabaseBackendService
    ) {
        self.persistence = persistence
        self.repository = repository
        self.backend = backend
    }

    @discardableResult
    func synchronize(account: OneCartAccount) async throws -> [RemoteFamilySummary] {
        try await repository.claimUnassignedFamilySpaces(for: account.id)
        let localFamilies = try await localFamilyMetadata(for: account.id)

        for family in localFamilies where family.needsRemoteCreation || family.role == "owner" {
            try await backend.ensureFamily(
                id: family.id,
                name: family.name,
                createdAt: family.createdAt,
                updatedAt: family.updatedAt
            )
        }

        let remoteFamilies = try await backend.families()
        let localByID = Dictionary(uniqueKeysWithValues: localFamilies.map { ($0.id, $0) })

        for remoteFamily in remoteFamilies {
            let canonicalSnapshot: FamilySnapshot
            if localByID[remoteFamily.id] != nil {
                let localSnapshot = try await makeSnapshot(familyID: remoteFamily.id)
                canonicalSnapshot = try await backend.synchronize(
                    familyID: remoteFamily.id,
                    snapshot: localSnapshot
                )
            } else {
                canonicalSnapshot = try await backend.snapshot(familyID: remoteFamily.id)
            }

            try await apply(
                snapshot: canonicalSnapshot,
                summary: remoteFamily,
                accountID: account.id
            )
        }

        let remoteIDs = Set(remoteFamilies.map(\.id))
        for localFamily in localFamilies
        where !remoteIDs.contains(localFamily.id) && !localFamily.needsRemoteCreation {
            try await repository.removeCachedFamilySpace(
                id: localFamily.id,
                for: account.id
            )
        }

        return remoteFamilies
    }

    func localFamilyMetadata(for userID: UUID) async throws -> [LocalFamilyMetadata] {
        try await persistence.performBackgroundTask(author: "OneCartSyncRead") { context in
            let request = FamilySpace.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "cachedForUserID == %@", userID as NSUUID),
                NSPredicate(format: "deletedAt == nil"),
            ])
            return try context.fetch(request).compactMap { family in
                guard let id = family.id else { return nil }
                let createdAt = family.createdAt ?? family.updatedAt ?? Date()
                return LocalFamilyMetadata(
                    id: id,
                    name: family.displayName,
                    createdAt: createdAt,
                    updatedAt: family.updatedAt ?? createdAt,
                    role: family.serverRole,
                    needsRemoteCreation: family.needsRemoteCreationValue
                )
            }
        }
    }

    func makeSnapshot(familyID: UUID) async throws -> FamilySnapshot {
        try await persistence.performBackgroundTask(author: "OneCartSnapshotRead") { context in
            let family = try Self.requireFamily(id: familyID, in: context)

            let stores = (family.stores?.allObjects as? [StoreEntity] ?? []).compactMap {
                object -> RemoteStore? in
                guard let id = object.id else { return nil }
                let createdAt = object.createdAt ?? object.updatedAt ?? Date()
                return RemoteStore(
                    id: id,
                    familyID: familyID,
                    name: object.displayName,
                    icon: object.icon ?? "",
                    colorHex: object.displayColorHex,
                    address: object.address,
                    latitude: object.latitudeValue,
                    longitude: object.longitudeValue,
                    externalAppURL: object.externalAppURL,
                    isPinned: object.isPinnedValue,
                    createdAt: createdAt,
                    updatedAt: object.updatedAt ?? createdAt,
                    deletedAt: object.deletedAt
                )
            }

            let lists = (family.lists?.allObjects as? [ShoppingListEntity] ?? []).compactMap {
                object -> RemoteShoppingList? in
                guard let id = object.id else { return nil }
                let createdAt = object.createdAt ?? object.updatedAt ?? Date()
                return RemoteShoppingList(
                    id: id,
                    familyID: familyID,
                    storeID: object.store?.id,
                    title: object.displayTitle,
                    status: object.statusValue.rawValue,
                    createdAt: createdAt,
                    updatedAt: object.updatedAt ?? createdAt,
                    deletedAt: object.deletedAt
                )
            }

            let products = (family.products?.allObjects as? [ProductEntity] ?? []).compactMap {
                object -> RemoteProduct? in
                guard let id = object.id, let listID = object.list?.id else { return nil }
                let createdAt = object.createdAt ?? object.updatedAt ?? Date()
                return RemoteProduct(
                    id: id,
                    familyID: familyID,
                    listID: listID,
                    storeID: object.store?.id,
                    name: object.displayName,
                    quantity: max(object.quantity?.doubleValue ?? 1, 0.001),
                    unit: object.unitValue.rawValue,
                    category: object.categoryValue.rawValue,
                    estimatedPrice: object.estimatedPriceValue,
                    originalPrice: object.originalPrice?.doubleValue,
                    imageURL: object.imageURL,
                    sourceURL: object.sourceURL,
                    note: object.note ?? "",
                    isPurchased: object.isPurchasedValue,
                    purchasedAt: object.purchasedAt,
                    purchasedByName: object.purchasedByName,
                    createdAt: createdAt,
                    updatedAt: object.updatedAt ?? createdAt,
                    deletedAt: object.deletedAt
                )
            }

            let history = (family.historyEntries?.allObjects as? [PurchaseHistoryEntity] ?? [])
                .compactMap { object -> RemotePurchaseHistory? in
                    guard let id = object.id else { return nil }
                    let createdAt = object.createdAt ?? object.date ?? object.updatedAt ?? Date()
                    return RemotePurchaseHistory(
                        id: id,
                        familyID: familyID,
                        storeID: object.store?.id,
                        total: object.totalValue,
                        purchasedAt: object.date ?? createdAt,
                        memberNames: object.membersDisplay,
                        createdAt: createdAt,
                        updatedAt: object.updatedAt ?? createdAt,
                        deletedAt: object.deletedAt
                    )
                }

            let historyItems = (family.historyItems?.allObjects as? [HistoryItemEntity] ?? [])
                .compactMap { object -> RemoteHistoryItem? in
                    guard let id = object.id, let historyID = object.history?.id else { return nil }
                    let createdAt = object.createdAt ?? object.updatedAt ?? Date()
                    return RemoteHistoryItem(
                        id: id,
                        familyID: familyID,
                        historyID: historyID,
                        name: object.displayName,
                        quantity: max(object.quantity?.doubleValue ?? 1, 0.001),
                        unit: object.unitValue.rawValue,
                        category: ProductCategory(rawValue: object.category ?? "")?.rawValue
                            ?? ProductCategory.other.rawValue,
                        estimatedPrice: object.estimatedPriceValue,
                        note: object.note ?? "",
                        purchasedAt: object.purchasedAt,
                        purchasedByName: object.purchasedByName,
                        storeName: object.storeName,
                        createdAt: createdAt,
                        updatedAt: object.updatedAt ?? createdAt,
                        deletedAt: object.deletedAt
                    )
                }

            return FamilySnapshot(
                family: nil,
                stores: stores,
                shoppingLists: lists,
                products: products,
                purchaseHistory: history,
                historyItems: historyItems
            )
        }
    }

    func apply(
        snapshot: FamilySnapshot,
        summary: RemoteFamilySummary,
        accountID: UUID
    ) async throws {
        try await persistence.performBackgroundTask(author: "OneCartSnapshotMerge") { context in
            let family = try Self.family(
                id: summary.id,
                createIfNeededIn: context,
                persistence: self.persistence
            )
            family.cachedForUserID = accountID
            family.serverRole = summary.access.rawValue
            family.needsRemoteCreation = false
            family.name = snapshot.family?.name ?? summary.name
            family.createdAt = snapshot.family?.createdAt ?? summary.createdAt
            family.updatedAt = snapshot.family?.updatedAt ?? summary.updatedAt
            family.deletedAt = snapshot.family?.deletedAt

            var storeByID = try Self.existingStores(familyID: summary.id, in: context)
            for row in snapshot.stores {
                let object = try Self.store(
                    id: row.id,
                    family: family,
                    existing: &storeByID,
                    context: context,
                    persistence: self.persistence
                )
                guard Self.shouldApply(remoteDate: row.updatedAt, to: object.updatedAt) else {
                    continue
                }
                object.name = row.name
                object.icon = row.icon
                object.colorHex = row.colorHex
                object.address = row.address
                object.latitude = row.latitude.map(NSNumber.init(value:))
                object.longitude = row.longitude.map(NSNumber.init(value:))
                object.externalAppURL = row.externalAppURL
                object.isPinned = NSNumber(value: row.isPinned)
                object.createdAt = row.createdAt
                object.updatedAt = row.updatedAt
                object.deletedAt = row.deletedAt
                object.familySpace = family
            }

            var listByID = try Self.existingLists(familyID: summary.id, in: context)
            for row in snapshot.shoppingLists {
                let object = try Self.list(
                    id: row.id,
                    family: family,
                    existing: &listByID,
                    context: context,
                    persistence: self.persistence
                )
                guard Self.shouldApply(remoteDate: row.updatedAt, to: object.updatedAt) else {
                    continue
                }
                object.title = row.title
                object.status = ShoppingListStatus(rawValue: row.status)?.rawValue
                    ?? ShoppingListStatus.active.rawValue
                object.createdAt = row.createdAt
                object.updatedAt = row.updatedAt
                object.deletedAt = row.deletedAt
                object.familySpace = family
                object.store = row.storeID.flatMap { storeByID[$0] }
            }

            var productByID = try Self.existingProducts(familyID: summary.id, in: context)
            for row in snapshot.products {
                guard let list = listByID[row.listID] else { continue }
                let object = try Self.product(
                    id: row.id,
                    family: family,
                    existing: &productByID,
                    context: context,
                    persistence: self.persistence
                )
                guard Self.shouldApply(remoteDate: row.updatedAt, to: object.updatedAt) else {
                    continue
                }
                object.name = row.name
                object.quantity = NSNumber(value: max(row.quantity, 0.001))
                object.unit = ProductUnit(rawValue: row.unit)?.rawValue ?? ProductUnit.piece.rawValue
                object.category = ProductCategory(rawValue: row.category)?.rawValue
                    ?? ProductCategory.other.rawValue
                object.estimatedPrice = NSNumber(value: max(row.estimatedPrice, 0))
                object.originalPrice = row.originalPrice.map(NSNumber.init(value:))
                object.imageURL = row.imageURL
                object.sourceURL = row.sourceURL
                object.note = row.note
                object.isPurchased = NSNumber(value: row.isPurchased)
                object.purchasedAt = row.purchasedAt
                object.purchasedByName = row.purchasedByName
                object.createdAt = row.createdAt
                object.updatedAt = row.updatedAt
                object.deletedAt = row.deletedAt
                object.familySpace = family
                object.list = list
                object.store = row.storeID.flatMap { storeByID[$0] }
            }

            var historyByID = try Self.existingHistory(familyID: summary.id, in: context)
            for row in snapshot.purchaseHistory {
                let object = try Self.history(
                    id: row.id,
                    family: family,
                    existing: &historyByID,
                    context: context,
                    persistence: self.persistence
                )
                guard Self.shouldApply(remoteDate: row.updatedAt, to: object.updatedAt) else {
                    continue
                }
                object.total = NSNumber(value: max(row.total, 0))
                object.date = row.purchasedAt
                object.memberNames = row.memberNames
                object.createdAt = row.createdAt
                object.updatedAt = row.updatedAt
                object.deletedAt = row.deletedAt
                object.familySpace = family
                object.store = row.storeID.flatMap { storeByID[$0] }
            }

            var itemByID = try Self.existingHistoryItems(familyID: summary.id, in: context)
            for row in snapshot.historyItems {
                guard let history = historyByID[row.historyID] else { continue }
                let object = try Self.historyItem(
                    id: row.id,
                    family: family,
                    existing: &itemByID,
                    context: context,
                    persistence: self.persistence
                )
                guard Self.shouldApply(remoteDate: row.updatedAt, to: object.updatedAt) else {
                    continue
                }
                object.name = row.name
                object.quantity = NSNumber(value: max(row.quantity, 0.001))
                object.unit = ProductUnit(rawValue: row.unit)?.rawValue ?? ProductUnit.piece.rawValue
                object.category = ProductCategory(rawValue: row.category)?.rawValue
                    ?? ProductCategory.other.rawValue
                object.estimatedPrice = NSNumber(value: max(row.estimatedPrice, 0))
                object.note = row.note
                object.purchasedAt = row.purchasedAt
                object.purchasedByName = row.purchasedByName
                object.storeName = row.storeName
                object.createdAt = row.createdAt
                object.updatedAt = row.updatedAt
                object.deletedAt = row.deletedAt
                object.familySpace = family
                object.history = history
            }
        }
    }

    private static func shouldApply(remoteDate: Date, to localDate: Date?) -> Bool {
        remoteDate >= (localDate ?? .distantPast)
    }

    private static func requireFamily(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        guard let family = try context.fetch(request).first else {
            throw RepositoryError.familySpaceNotFound
        }
        return family
    }

    private static func family(
        id: UUID,
        createIfNeededIn context: NSManagedObjectContext,
        persistence: PersistenceController
    ) throws -> FamilySpace {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first { return existing }

        let object = FamilySpace(context: context)
        try persistence.assign(object, to: .private, in: context)
        object.id = id
        return object
    }

    private static func existingStores(
        familyID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [UUID: StoreEntity] {
        try existingObjects(
            request: StoreEntity.fetchRequest(),
            familyID: familyID,
            id: { $0.id },
            in: context
        )
    }

    private static func existingLists(
        familyID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [UUID: ShoppingListEntity] {
        try existingObjects(
            request: ShoppingListEntity.fetchRequest(),
            familyID: familyID,
            id: { $0.id },
            in: context
        )
    }

    private static func existingProducts(
        familyID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [UUID: ProductEntity] {
        try existingObjects(
            request: ProductEntity.fetchRequest(),
            familyID: familyID,
            id: { $0.id },
            in: context
        )
    }

    private static func existingHistory(
        familyID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [UUID: PurchaseHistoryEntity] {
        try existingObjects(
            request: PurchaseHistoryEntity.fetchRequest(),
            familyID: familyID,
            id: { $0.id },
            in: context
        )
    }

    private static func existingHistoryItems(
        familyID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [UUID: HistoryItemEntity] {
        try existingObjects(
            request: HistoryItemEntity.fetchRequest(),
            familyID: familyID,
            id: { $0.id },
            in: context
        )
    }

    private static func existingObjects<T: NSManagedObject>(
        request: NSFetchRequest<T>,
        familyID: UUID,
        id: (T) -> UUID?,
        in context: NSManagedObjectContext
    ) throws -> [UUID: T] {
        request.predicate = NSPredicate(format: "familySpace.id == %@", familyID as NSUUID)
        var result: [UUID: T] = [:]
        for object in try context.fetch(request) {
            if let objectID = id(object) {
                result[objectID] = object
            }
        }
        return result
    }

    private static func store(
        id: UUID,
        family: FamilySpace,
        existing: inout [UUID: StoreEntity],
        context: NSManagedObjectContext,
        persistence: PersistenceController
    ) throws -> StoreEntity {
        if let object = existing[id] { return object }
        let object = StoreEntity(context: context)
        try persistence.assign(object, toSameStoreAs: family, in: context)
        object.id = id
        object.familySpace = family
        existing[id] = object
        return object
    }

    private static func list(
        id: UUID,
        family: FamilySpace,
        existing: inout [UUID: ShoppingListEntity],
        context: NSManagedObjectContext,
        persistence: PersistenceController
    ) throws -> ShoppingListEntity {
        if let object = existing[id] { return object }
        let object = ShoppingListEntity(context: context)
        try persistence.assign(object, toSameStoreAs: family, in: context)
        object.id = id
        object.familySpace = family
        existing[id] = object
        return object
    }

    private static func product(
        id: UUID,
        family: FamilySpace,
        existing: inout [UUID: ProductEntity],
        context: NSManagedObjectContext,
        persistence: PersistenceController
    ) throws -> ProductEntity {
        if let object = existing[id] { return object }
        let object = ProductEntity(context: context)
        try persistence.assign(object, toSameStoreAs: family, in: context)
        object.id = id
        object.familySpace = family
        existing[id] = object
        return object
    }

    private static func history(
        id: UUID,
        family: FamilySpace,
        existing: inout [UUID: PurchaseHistoryEntity],
        context: NSManagedObjectContext,
        persistence: PersistenceController
    ) throws -> PurchaseHistoryEntity {
        if let object = existing[id] { return object }
        let object = PurchaseHistoryEntity(context: context)
        try persistence.assign(object, toSameStoreAs: family, in: context)
        object.id = id
        object.familySpace = family
        existing[id] = object
        return object
    }

    private static func historyItem(
        id: UUID,
        family: FamilySpace,
        existing: inout [UUID: HistoryItemEntity],
        context: NSManagedObjectContext,
        persistence: PersistenceController
    ) throws -> HistoryItemEntity {
        if let object = existing[id] { return object }
        let object = HistoryItemEntity(context: context)
        try persistence.assign(object, toSameStoreAs: family, in: context)
        object.id = id
        object.familySpace = family
        existing[id] = object
        return object
    }
}
