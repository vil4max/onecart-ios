import CoreData
import CryptoKit
import Foundation

enum LegacyMigrationResult: Equatable {
    case noData
    case alreadyMigrated(UUID)
    case migrated(UUID)
}

protocol LegacySnapshotProviding {
    func loadSnapshotData() -> Data?
}

struct DefaultLegacySnapshotProvider: LegacySnapshotProviding {
    private let userDefaults: UserDefaults
    private let fileManager: FileManager

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func loadSnapshotData() -> Data? {
        if let data = userDefaults.data(forKey: "onecart.app-state") {
            return data
        }
        if let value = userDefaults.string(forKey: "onecart.app-state") {
            return Data(value.utf8)
        }

        let candidates = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("onecart.app-state.json"),
            fileManager.urls(for: .documentDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("onecart-backup.json"),
        ]

        for url in candidates.compactMap({ $0 }) where fileManager.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return data
            }
        }
        return nil
    }
}

final class LegacyMigrationService {
    static let legacyFamilySpaceID = UUID.deterministic("onecart.legacy.family-space.v1")

    private let persistence: PersistenceController
    private let userDefaults: UserDefaults

    init(
        persistence: PersistenceController,
        userDefaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.userDefaults = userDefaults
    }

    func migrateIfNeeded(data: Data?) async throws -> LegacyMigrationResult {
        guard let data, !data.isEmpty else { return .noData }

        let envelope = try JSONDecoder().decode(LegacyEnvelope.self, from: data)
        let familySpaceID = Self.legacyFamilySpaceID
        let state = envelope.state

        let result: LegacyMigrationResult = try await persistence.performBackgroundTask(
            author: "OneCartLegacyMigration"
        ) { context in
            let existingRequest = FamilySpace.fetchRequest()
            existingRequest.predicate = NSPredicate(
                format: "id == %@",
                familySpaceID as NSUUID
            )
            existingRequest.fetchLimit = 1
            if try context.fetch(existingRequest).first != nil {
                return .alreadyMigrated(familySpaceID)
            }

            let now = envelope.savedAt.flatMap(Self.parseDate) ?? Date()
            let space = FamilySpace(context: context)
            try self.persistence.assign(space, to: .private, in: context)
            space.id = familySpaceID
            space.name = "Группа"
            space.createdAt = now
            space.updatedAt = now

            var storeByLegacyID: [String: StoreEntity] = [:]
            for legacyStore in state.stores {
                let store = StoreEntity(context: context)
                try self.persistence.assign(store, toSameStoreAs: space, in: context)
                store.id = UUID.deterministic("onecart.legacy.store.\(legacyStore.id)")
                store.name = legacyStore.name
                store.icon = legacyStore.icon
                store.colorHex = legacyStore.color
                store.address = legacyStore.address
                store.externalAppURL = legacyStore.externalAppUrl
                store.isPinned = NSNumber(value: legacyStore.isPinned)
                store.createdAt = now
                store.updatedAt = now
                store.familySpace = space
                storeByLegacyID[legacyStore.id] = store
            }

            var listByLegacyID: [String: ShoppingListEntity] = [:]
            for legacyList in state.shoppingLists {
                let list = ShoppingListEntity(context: context)
                try self.persistence.assign(list, toSameStoreAs: space, in: context)
                list.id = UUID.deterministic("onecart.legacy.list.\(legacyList.id)")
                list.title = legacyList.title
                list.status = ShoppingListStatus(rawValue: legacyList.status)?.rawValue
                    ?? ShoppingListStatus.active.rawValue
                list.createdAt = Self.parseDate(legacyList.createdAt) ?? now
                list.updatedAt = Self.parseDate(legacyList.updatedAt) ?? list.createdAt
                list.familySpace = space
                list.store = legacyList.storeId.flatMap { storeByLegacyID[$0] }
                listByLegacyID[legacyList.id] = list
            }

            var fallbackList = listByLegacyID.values.first(where: { $0.store == nil })

            for legacyProduct in state.products {
                let product = ProductEntity(context: context)
                try self.persistence.assign(product, toSameStoreAs: space, in: context)
                product.id = UUID.deterministic("onecart.legacy.product.\(legacyProduct.id)")
                Self.apply(legacyProduct, to: product, fallbackDate: now)
                let list: ShoppingListEntity
                if let existingList = listByLegacyID[legacyProduct.listId] {
                    list = existingList
                } else if let existingFallback = fallbackList {
                    list = existingFallback
                } else {
                    let general = ShoppingListEntity(context: context)
                    try self.persistence.assign(general, toSameStoreAs: space, in: context)
                    general.id = UUID.deterministic("onecart.legacy.list.general-fallback")
                    general.title = "Общий список"
                    general.status = ShoppingListStatus.active.rawValue
                    general.createdAt = now
                    general.updatedAt = now
                    general.familySpace = space
                    fallbackList = general
                    list = general
                }
                product.familySpace = space
                product.list = list
                product.store = legacyProduct.storeId.flatMap { storeByLegacyID[$0] } ?? list.store
            }

            let userNames = Dictionary(
                uniqueKeysWithValues: state.users.map { ($0.id, $0.name) }
            )
            for legacyHistory in state.purchaseHistory {
                let history = PurchaseHistoryEntity(context: context)
                try self.persistence.assign(history, toSameStoreAs: space, in: context)
                history.id = UUID.deterministic(
                    "onecart.legacy.history.\(legacyHistory.id)"
                )
                history.total = NSNumber(value: max(legacyHistory.total, 0))
                history.date = Self.parseDate(legacyHistory.date) ?? now
                history.createdAt = history.date
                history.updatedAt = history.date
                history.memberNames = legacyHistory.members
                    .compactMap { userNames[$0] }
                    .joined(separator: ", ")
                history.familySpace = space
                history.store = legacyHistory.storeId.flatMap { storeByLegacyID[$0] }

                for legacyProduct in legacyHistory.products {
                    let item = HistoryItemEntity(context: context)
                    try self.persistence.assign(item, toSameStoreAs: space, in: context)
                    item.id = UUID.deterministic(
                        "onecart.legacy.history-item.\(legacyHistory.id).\(legacyProduct.id)"
                    )
                    item.name = legacyProduct.name
                    item.quantity = NSNumber(value: max(legacyProduct.quantity, 0))
                    item.unit = ProductUnit(rawValue: legacyProduct.unit)?.rawValue
                        ?? ProductUnit.piece.rawValue
                    item.category = ProductCategory(rawValue: legacyProduct.category)?.rawValue
                        ?? ProductCategory.other.rawValue
                    item.estimatedPrice = NSNumber(value: max(legacyProduct.estimatedPrice, 0))
                    item.note = legacyProduct.note
                    item.purchasedAt = legacyProduct.purchasedAt.flatMap(Self.parseDate)
                    item.storeName = legacyProduct.storeId
                        .flatMap { storeByLegacyID[$0]?.name }
                    item.createdAt = Self.parseDate(legacyProduct.createdAt) ?? history.date
                    item.updatedAt = history.date
                    item.familySpace = space
                    item.history = history
                }
            }

            return .migrated(familySpaceID)
        }

        if case .migrated = result {
            userDefaults.set(true, forKey: "onecart.coredata.legacy-migration-v1")
            if let settings = state.settings {
                userDefaults.set(settings.locale, forKey: "onecart.locale")
                userDefaults.set(settings.theme, forKey: "onecart.theme")
                userDefaults.set(settings.defaultUnit, forKey: "onecart.default-unit")
            }
            if let currentUserID = state.currentUserId,
               let currentName = state.users.first(where: { $0.id == currentUserID })?.name {
                userDefaults.set(currentName, forKey: "onecart.participant-display-name")
            }
        }

        return result
    }

    private static func apply(
        _ legacy: LegacyProduct,
        to product: ProductEntity,
        fallbackDate: Date
    ) {
        let createdAt = parseDate(legacy.createdAt) ?? fallbackDate
        let purchasedAt = legacy.purchasedAt.flatMap(parseDate)
        product.name = legacy.name
        product.quantity = NSNumber(value: max(legacy.quantity, 0.001))
        product.unit = ProductUnit(rawValue: legacy.unit)?.rawValue
            ?? ProductUnit.piece.rawValue
        product.category = ProductCategory(rawValue: legacy.category)?.rawValue
            ?? ProductCategory.other.rawValue
        product.estimatedPrice = NSNumber(value: max(legacy.estimatedPrice, 0))
        product.note = legacy.note
        product.isPurchased = NSNumber(value: legacy.isPurchased)
        product.createdAt = createdAt
        product.updatedAt = purchasedAt ?? createdAt
        product.purchasedAt = purchasedAt
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter.fractional.date(from: value)
            ?? ISO8601DateFormatter.standard.date(from: value)
    }
}

private struct LegacyEnvelope: Decodable {
    let version: Int?
    let savedAt: String?
    let state: LegacyState
}

private struct LegacyState: Decodable {
    let users: [LegacyUser]
    let currentUserId: String?
    let stores: [LegacyStore]
    let shoppingLists: [LegacyShoppingList]
    let products: [LegacyProduct]
    let purchaseHistory: [LegacyPurchaseHistory]
    let settings: LegacySettings?

    private enum CodingKeys: String, CodingKey {
        case users
        case currentUserId
        case stores
        case shoppingLists
        case products
        case purchaseHistory
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([LegacyUser].self, forKey: .users) ?? []
        currentUserId = try container.decodeIfPresent(String.self, forKey: .currentUserId)
        stores = try container.decodeIfPresent([LegacyStore].self, forKey: .stores) ?? []
        shoppingLists = try container.decodeIfPresent(
            [LegacyShoppingList].self,
            forKey: .shoppingLists
        ) ?? []
        products = try container.decodeIfPresent([LegacyProduct].self, forKey: .products) ?? []
        purchaseHistory = try container.decodeIfPresent(
            [LegacyPurchaseHistory].self,
            forKey: .purchaseHistory
        ) ?? []
        settings = try container.decodeIfPresent(LegacySettings.self, forKey: .settings)
    }
}

private struct LegacyUser: Decodable {
    let id: String
    let name: String
}

private struct LegacyStore: Decodable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let address: String?
    let externalAppUrl: String?
    let isPinned: Bool
}

private struct LegacyShoppingList: Decodable {
    let id: String
    let title: String
    let storeId: String?
    let createdAt: String
    let updatedAt: String
    let status: String
}

private struct LegacyProduct: Decodable {
    let id: String
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let estimatedPrice: Double
    let note: String
    let storeId: String?
    let listId: String
    let isPurchased: Bool
    let createdAt: String
    let purchasedAt: String?
}

private struct LegacyPurchaseHistory: Decodable {
    let id: String
    let storeId: String?
    let products: [LegacyProduct]
    let total: Double
    let date: String
    let members: [String]
}

private struct LegacySettings: Decodable {
    let locale: String
    let theme: String
    let defaultUnit: String
}

private extension UUID {
    static func deterministic(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
