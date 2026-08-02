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
        name?.nilIfBlank ?? String(localized: "common.default_group")
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
            return $0.createdDate > $1.createdDate
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
        name?.nilIfBlank ?? String(localized: "common.default_store")
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
        title?.nilIfBlank ?? String(localized: "cart.default_title")
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
            return $0.createdDate > $1.createdDate
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
        case .piece: String(localized: "common.unit.piece")
        case .kg: String(localized: "common.unit.kg")
        case .g: String(localized: "common.unit.g")
        case .l: String(localized: "common.unit.l")
        case .ml: String(localized: "common.unit.ml")
        case .pack: String(localized: "common.unit.pack")
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
    @NSManaged var createdByName: String?
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
        name?.nilIfBlank ?? String(localized: "common.default_product")
    }

    var quantityValue: Double {
        max(quantity?.doubleValue ?? 1, 0)
    }

    var unitValue: ProductUnit {
        ProductUnit(rawValue: unit ?? "") ?? .piece
    }

    var categoryValue: ProductCategory {
        ProductCategory.resolved(storedRawValue: category)
    }

    var estimatedPriceValue: Double {
        max(estimatedPrice?.doubleValue ?? 0, 0)
    }

    var originalPriceValue: Double? {
        if let promotionEndsAt, promotionEndsAt <= Date() {
            return nil
        }
        guard let value = originalPrice?.doubleValue, value > estimatedPriceValue else { return nil }
        return value
    }

    var loyaltyPriceValue: Double? {
        if let promotionEndsAt, promotionEndsAt <= Date() {
            return nil
        }
        guard let value = loyaltyPrice?.doubleValue,
              value > 0,
              value < estimatedPriceValue else { return nil }
        return value
    }

    var isCatalogPriceStale: Bool {
        guard sourceURLValue != nil else { return false }
        guard let catalogFetchedAt else { return true }
        if let promotionEndsAt, promotionEndsAt <= Date() {
            return true
        }
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
        memberNames?.nilIfBlank ?? String(localized: "common.default_group")
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
        name?.nilIfBlank ?? String(localized: "common.default_product")
    }

    var quantityValue: Double {
        max(quantity?.doubleValue ?? 1, 0)
    }

    var unitValue: ProductUnit {
        ProductUnit(rawValue: unit ?? "") ?? .piece
    }

    var categoryValue: ProductCategory {
        ProductCategory.resolved(storedRawValue: category)
    }

    var purchaseMoment: Date {
        purchasedAt ?? createdAt ?? history?.purchaseDate ?? .distantPast
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
