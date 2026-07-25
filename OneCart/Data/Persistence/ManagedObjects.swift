import CoreData
import Foundation

@objc(FamilySpace)
final class FamilySpace: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var cachedForUserID: UUID?
    @NSManaged var serverRole: String?
    @NSManaged var needsRemoteCreation: NSNumber?
    @NSManaged var isHouseholdDefault: NSNumber?
    @NSManaged var stores: NSSet?
    @NSManaged var lists: NSSet?
    @NSManaged var products: NSSet?
    @NSManaged var historyEntries: NSSet?
    @NSManaged var historyItems: NSSet?

    @nonobjc class func fetchRequest() -> NSFetchRequest<FamilySpace> {
        NSFetchRequest<FamilySpace>(entityName: "FamilySpace")
    }

    var stableID: UUID {
        id ?? UUID()
    }

    var displayName: String {
        name?.nilIfBlank ?? "Группа"
    }

    var createdDate: Date {
        createdAt ?? .distantPast
    }

    var updatedDate: Date {
        updatedAt ?? createdDate
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }

    var needsRemoteCreationValue: Bool {
        needsRemoteCreation?.boolValue ?? false
    }

    var isHouseholdDefaultValue: Bool {
        isHouseholdDefault?.boolValue ?? false
    }

    var sortedStores: [StoreEntity] {
        let values = (stores?.allObjects as? [StoreEntity] ?? [])
            .filter { !$0.isDeletedValue }
        return values.sorted {
            if $0.isPinnedValue != $1.isPinnedValue {
                return $0.isPinnedValue && !$1.isPinnedValue
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var sortedLists: [ShoppingListEntity] {
        let values = (lists?.allObjects as? [ShoppingListEntity] ?? [])
            .filter { !$0.isDeletedValue }
        return values.sorted {
            if $0.statusValue != $1.statusValue {
                return $0.statusValue == .active
            }
            return $0.updatedDate > $1.updatedDate
        }
    }

    var activeLists: [ShoppingListEntity] {
        sortedLists.filter { $0.statusValue == .active }
    }

    var sortedProducts: [ProductEntity] {
        let values = (products?.allObjects as? [ProductEntity] ?? [])
            .filter { !$0.isDeletedValue }
        return values.sorted {
            if $0.isPurchasedValue != $1.isPurchasedValue {
                return !$0.isPurchasedValue && $1.isPurchasedValue
            }
            return $0.createdDate < $1.createdDate
        }
    }

    var sortedHistory: [PurchaseHistoryEntity] {
        let values = (historyEntries?.allObjects as? [PurchaseHistoryEntity] ?? [])
            .filter { !$0.isDeletedValue }
        return values.sorted { $0.purchaseDate > $1.purchaseDate }
    }
}

@objc(StoreEntity)
final class StoreEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var icon: String?
    @NSManaged var colorHex: String?
    @NSManaged var address: String?
    @NSManaged var latitude: NSNumber?
    @NSManaged var longitude: NSNumber?
    @NSManaged var externalAppURL: String?
    @NSManaged var isPinned: NSNumber?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var familySpace: FamilySpace?
    @NSManaged var lists: NSSet?
    @NSManaged var products: NSSet?
    @NSManaged var historyEntries: NSSet?

    @nonobjc class func fetchRequest() -> NSFetchRequest<StoreEntity> {
        NSFetchRequest<StoreEntity>(entityName: "Store")
    }

    var stableID: UUID {
        id ?? UUID()
    }

    var displayName: String {
        name?.nilIfBlank ?? "Магазин"
    }

    var displayIcon: String {
        icon?.nilIfBlank ?? String(displayName.prefix(2)).uppercased()
    }

    var displayColorHex: String {
        colorHex?.nilIfBlank ?? "#34785B"
    }

    var latitudeValue: Double? {
        latitude?.doubleValue
    }

    var longitudeValue: Double? {
        longitude?.doubleValue
    }

    var isPinnedValue: Bool {
        isPinned?.boolValue ?? false
    }

    var createdDate: Date {
        createdAt ?? .distantPast
    }

    var updatedDate: Date {
        updatedAt ?? createdDate
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }

    var activeList: ShoppingListEntity? {
        let values = lists?.allObjects as? [ShoppingListEntity] ?? []
        return values
            .filter { !$0.isDeletedValue && $0.statusValue == .active }
            .sorted { $0.updatedDate > $1.updatedDate }
            .first
    }
}

extension StoreEntity: Identifiable {
    typealias ID = UUID?
}

enum ShoppingListStatus: String, CaseIterable {
    case active
    case completed
    case archived
}

@objc(ShoppingListEntity)
final class ShoppingListEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var status: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var familySpace: FamilySpace?
    @NSManaged var store: StoreEntity?
    @NSManaged var products: NSSet?

    @nonobjc class func fetchRequest() -> NSFetchRequest<ShoppingListEntity> {
        NSFetchRequest<ShoppingListEntity>(entityName: "ShoppingList")
    }

    var stableID: UUID {
        id ?? UUID()
    }

    var displayTitle: String {
        title?.nilIfBlank ?? "Список покупок"
    }

    var statusValue: ShoppingListStatus {
        ShoppingListStatus(rawValue: status ?? "") ?? .active
    }

    var createdDate: Date {
        createdAt ?? .distantPast
    }

    var updatedDate: Date {
        updatedAt ?? createdDate
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }

    var sortedProducts: [ProductEntity] {
        let values = (products?.allObjects as? [ProductEntity] ?? [])
            .filter { !$0.isDeletedValue }
        return values.sorted {
            if $0.isPurchasedValue != $1.isPurchasedValue {
                return !$0.isPurchasedValue && $1.isPurchasedValue
            }
            return $0.createdDate < $1.createdDate
        }
    }

    var estimatedTotal: Double {
        sortedProducts.reduce(0) { $0 + $1.estimatedPriceValue }
    }
}

enum ProductUnit: String, CaseIterable, Identifiable {
    case piece
    case kg
    case g
    case l
    case ml
    case pack

    var id: String {
        rawValue
    }

    var localizedName: String {
        switch self {
        case .piece: "шт."
        case .kg: "кг"
        case .g: "г"
        case .l: "л"
        case .ml: "мл"
        case .pack: "уп."
        }
    }
}

enum ProductCategory: String, CaseIterable, Identifiable {
    case produce
    case dairy
    case meat
    case drinks
    case household
    case other

    var id: String {
        rawValue
    }

    var localizedName: String {
        switch self {
        case .produce: "Овощи и фрукты"
        case .dairy: "Молочное"
        case .meat: "Мясо"
        case .drinks: "Напитки"
        case .household: "Для дома"
        case .other: "Другое"
        }
    }
}

@objc(ProductEntity)
final class ProductEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: NSNumber?
    @NSManaged var unit: String?
    @NSManaged var category: String?
    @NSManaged var estimatedPrice: NSNumber?
    @NSManaged var originalPrice: NSNumber?
    @NSManaged var loyaltyPrice: NSNumber?
    @NSManaged var imageURL: String?
    @NSManaged var sourceURL: String?
    @NSManaged var catalogFetchedAt: Date?
    @NSManaged var promotionEndsAt: Date?
    @NSManaged var note: String?
    @NSManaged var isPurchased: NSNumber?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var purchasedAt: Date?
    @NSManaged var purchasedByName: String?
    @NSManaged var deletedAt: Date?
    @NSManaged var familySpace: FamilySpace?
    @NSManaged var list: ShoppingListEntity?
    @NSManaged var store: StoreEntity?

    @nonobjc class func fetchRequest() -> NSFetchRequest<ProductEntity> {
        NSFetchRequest<ProductEntity>(entityName: "Product")
    }

    var stableID: UUID {
        id ?? UUID()
    }

    var displayName: String {
        name?.nilIfBlank ?? "Товар"
    }

    var quantityValue: Double {
        max(quantity?.doubleValue ?? 1, 0)
    }

    var unitValue: ProductUnit {
        ProductUnit(rawValue: unit ?? "") ?? .piece
    }

    var categoryValue: ProductCategory {
        ProductCategory(rawValue: category ?? "") ?? .other
    }

    var estimatedPriceValue: Double {
        max(estimatedPrice?.doubleValue ?? 0, 0)
    }

    var originalPriceValue: Double? {
        if let promotionEndsAt, promotionEndsAt <= Date() { return nil }
        guard let value = originalPrice?.doubleValue, value > estimatedPriceValue else { return nil }
        return value
    }

    var loyaltyPriceValue: Double? {
        if let promotionEndsAt, promotionEndsAt <= Date() { return nil }
        guard let value = loyaltyPrice?.doubleValue,
              value > 0,
              value < estimatedPriceValue else { return nil }
        return value
    }

    var isCatalogPriceStale: Bool {
        guard sourceURLValue != nil else { return false }
        guard let catalogFetchedAt else { return true }
        if let promotionEndsAt, promotionEndsAt <= Date() { return true }
        return Date().timeIntervalSince(catalogFetchedAt) > 5 * 60
    }

    var imageURLValue: URL? {
        imageURL.flatMap(URL.init(string:))
    }

    var sourceURLValue: URL? {
        sourceURL.flatMap(URL.init(string:))
    }

    var noteValue: String {
        note ?? ""
    }

    var isPurchasedValue: Bool {
        isPurchased?.boolValue ?? false
    }

    var createdDate: Date {
        createdAt ?? .distantPast
    }

    var updatedDate: Date {
        updatedAt ?? createdDate
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }
}

extension ProductEntity: Identifiable {
    typealias ID = UUID?
}

@objc(PurchaseHistoryEntity)
final class PurchaseHistoryEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var total: NSNumber?
    @NSManaged var date: Date?
    @NSManaged var memberNames: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var familySpace: FamilySpace?
    @NSManaged var store: StoreEntity?
    @NSManaged var items: NSSet?

    @nonobjc class func fetchRequest() -> NSFetchRequest<PurchaseHistoryEntity> {
        NSFetchRequest<PurchaseHistoryEntity>(entityName: "PurchaseHistory")
    }

    var stableID: UUID {
        id ?? UUID()
    }

    var totalValue: Double {
        max(total?.doubleValue ?? 0, 0)
    }

    var purchaseDate: Date {
        date ?? createdAt ?? .distantPast
    }

    var membersDisplay: String {
        memberNames?.nilIfBlank ?? "Группа"
    }

    var createdDate: Date {
        createdAt ?? purchaseDate
    }

    var updatedDate: Date {
        updatedAt ?? createdDate
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }

    var sortedItems: [HistoryItemEntity] {
        let values = (items?.allObjects as? [HistoryItemEntity] ?? [])
            .filter { !$0.isDeletedValue }
        return values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

@objc(HistoryItemEntity)
final class HistoryItemEntity: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: NSNumber?
    @NSManaged var unit: String?
    @NSManaged var category: String?
    @NSManaged var estimatedPrice: NSNumber?
    @NSManaged var originalPrice: NSNumber?
    @NSManaged var imageURL: String?
    @NSManaged var sourceURL: String?
    @NSManaged var note: String?
    @NSManaged var purchasedAt: Date?
    @NSManaged var purchasedByName: String?
    @NSManaged var storeName: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var familySpace: FamilySpace?
    @NSManaged var history: PurchaseHistoryEntity?

    @nonobjc class func fetchRequest() -> NSFetchRequest<HistoryItemEntity> {
        NSFetchRequest<HistoryItemEntity>(entityName: "HistoryItem")
    }

    var stableID: UUID {
        id ?? UUID()
    }

    var displayName: String {
        name?.nilIfBlank ?? "Товар"
    }

    var quantityValue: Double {
        max(quantity?.doubleValue ?? 1, 0)
    }

    var unitValue: ProductUnit {
        ProductUnit(rawValue: unit ?? "") ?? .piece
    }

    var categoryValue: ProductCategory {
        ProductCategory(rawValue: category ?? "") ?? .other
    }

    var estimatedPriceValue: Double {
        max(estimatedPrice?.doubleValue ?? 0, 0)
    }

    var originalPriceValue: Double? {
        guard let value = originalPrice?.doubleValue, value > estimatedPriceValue else { return nil }
        return value
    }

    var imageURLValue: URL? {
        imageURL.flatMap(URL.init(string:))
    }

    var sourceURLValue: URL? {
        sourceURL.flatMap(URL.init(string:))
    }

    var createdDate: Date {
        createdAt ?? .distantPast
    }

    var updatedDate: Date {
        updatedAt ?? createdDate
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }
}

enum OneCartManagedObjectModel {
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["OneCartCoreDataV6"]

        let familySpace = entity("FamilySpace", FamilySpace.self)
        let store = entity("Store", StoreEntity.self)
        let list = entity("ShoppingList", ShoppingListEntity.self)
        let product = entity("Product", ProductEntity.self)
        let history = entity("PurchaseHistory", PurchaseHistoryEntity.self)
        let historyItem = entity("HistoryItem", HistoryItemEntity.self)

        let familyStores = toMany("stores", destination: store, deleteRule: .cascadeDeleteRule)
        let storeFamily = toOne("familySpace", destination: familySpace)
        connect(familyStores, storeFamily)

        let familyLists = toMany("lists", destination: list, deleteRule: .cascadeDeleteRule)
        let listFamily = toOne("familySpace", destination: familySpace)
        connect(familyLists, listFamily)

        let familyProducts = toMany("products", destination: product, deleteRule: .cascadeDeleteRule)
        let productFamily = toOne("familySpace", destination: familySpace)
        connect(familyProducts, productFamily)

        let familyHistory = toMany("historyEntries", destination: history, deleteRule: .cascadeDeleteRule)
        let historyFamily = toOne("familySpace", destination: familySpace)
        connect(familyHistory, historyFamily)

        let familyHistoryItems = toMany("historyItems", destination: historyItem, deleteRule: .cascadeDeleteRule)
        let historyItemFamily = toOne("familySpace", destination: familySpace)
        connect(familyHistoryItems, historyItemFamily)

        let storeLists = toMany("lists", destination: list, deleteRule: .nullifyDeleteRule)
        let listStore = toOne("store", destination: store)
        connect(storeLists, listStore)

        let storeProducts = toMany("products", destination: product, deleteRule: .nullifyDeleteRule)
        let productStore = toOne("store", destination: store)
        connect(storeProducts, productStore)

        let storeHistory = toMany("historyEntries", destination: history, deleteRule: .nullifyDeleteRule)
        let historyStore = toOne("store", destination: store)
        connect(storeHistory, historyStore)

        let listProducts = toMany("products", destination: product, deleteRule: .cascadeDeleteRule)
        let productList = toOne("list", destination: list)
        connect(listProducts, productList)

        let historyItems = toMany("items", destination: historyItem, deleteRule: .cascadeDeleteRule)
        let itemHistory = toOne("history", destination: history)
        connect(historyItems, itemHistory)

        familySpace.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            attribute("cachedForUserID", .UUIDAttributeType),
            attribute("serverRole", .stringAttributeType),
            attribute("needsRemoteCreation", .booleanAttributeType),
            attribute("isHouseholdDefault", .booleanAttributeType),
            familyStores,
            familyLists,
            familyProducts,
            familyHistory,
            familyHistoryItems,
        ]

        store.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("icon", .stringAttributeType),
            attribute("colorHex", .stringAttributeType),
            attribute("address", .stringAttributeType),
            attribute("latitude", .doubleAttributeType),
            attribute("longitude", .doubleAttributeType),
            attribute("externalAppURL", .stringAttributeType),
            attribute("isPinned", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            storeFamily,
            storeLists,
            storeProducts,
            storeHistory,
        ]

        list.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("status", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            listFamily,
            listStore,
            listProducts,
        ]

        product.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("quantity", .doubleAttributeType),
            attribute("unit", .stringAttributeType),
            attribute("category", .stringAttributeType),
            attribute("estimatedPrice", .doubleAttributeType),
            attribute("originalPrice", .doubleAttributeType),
            attribute("loyaltyPrice", .doubleAttributeType),
            attribute("imageURL", .stringAttributeType),
            attribute("sourceURL", .stringAttributeType),
            attribute("catalogFetchedAt", .dateAttributeType),
            attribute("promotionEndsAt", .dateAttributeType),
            attribute("note", .stringAttributeType),
            attribute("isPurchased", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("purchasedAt", .dateAttributeType),
            attribute("purchasedByName", .stringAttributeType),
            attribute("deletedAt", .dateAttributeType),
            productFamily,
            productList,
            productStore,
        ]

        history.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("total", .doubleAttributeType),
            attribute("date", .dateAttributeType),
            attribute("memberNames", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            historyFamily,
            historyStore,
            historyItems,
        ]

        historyItem.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("quantity", .doubleAttributeType),
            attribute("unit", .stringAttributeType),
            attribute("category", .stringAttributeType),
            attribute("estimatedPrice", .doubleAttributeType),
            attribute("originalPrice", .doubleAttributeType),
            attribute("imageURL", .stringAttributeType),
            attribute("sourceURL", .stringAttributeType),
            attribute("note", .stringAttributeType),
            attribute("purchasedAt", .dateAttributeType),
            attribute("purchasedByName", .stringAttributeType),
            attribute("storeName", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            historyItemFamily,
            itemHistory,
        ]

        model.entities = [familySpace, store, list, product, history, historyItem]
        return model
    }

    private static func entity(_ name: String, _ type: NSManagedObject.Type) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(type)
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        return attribute
    }

    private static func toOne(
        _ name: String,
        destination: NSEntityDescription,
        deleteRule: NSDeleteRule = .nullifyDeleteRule
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = 0
        relationship.maxCount = 1
        relationship.isOptional = true
        relationship.deleteRule = deleteRule
        return relationship
    }

    private static func toMany(
        _ name: String,
        destination: NSEntityDescription,
        deleteRule: NSDeleteRule
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = 0
        relationship.maxCount = 0
        relationship.isOptional = true
        relationship.isOrdered = false
        relationship.deleteRule = deleteRule
        return relationship
    }

    private static func connect(
        _ first: NSRelationshipDescription,
        _ second: NSRelationshipDescription
    ) {
        first.inverseRelationship = second
        second.inverseRelationship = first
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
