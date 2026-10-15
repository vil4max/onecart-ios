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
    @NSManaged var memberProfiles: NSSet?

    @nonobjc static func fetchRequest() -> NSFetchRequest<FamilySpace> {
        NSFetchRequest<FamilySpace>(entityName: "FamilySpace")
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
            if $0.isActive != $1.isActive {
                return $0.isActive
            }
            return $0.updatedDate > $1.updatedDate
        }
    }

    var activeLists: [ShoppingListEntity] {
        sortedLists.filter(\.isActive)
    }

    var sortedProducts: [ProductEntity] {
        ProductEntity.liveInCartOrder(products)
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

    @nonobjc static func fetchRequest() -> NSFetchRequest<StoreEntity> {
        NSFetchRequest<StoreEntity>(entityName: "Store")
    }

    var displayName: String {
        name?.nilIfBlank ?? String(localized: "common.default_store")
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
}

extension StoreEntity: Identifiable {}

/// The only list status the app writes. v1.2.1 shows a list only while its status is "active",
/// so every list the app creates keeps writing it; the completed and archived values older builds
/// defined are never written now.
enum ShoppingListStatus: String {
    case active
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

    @nonobjc static func fetchRequest() -> NSFetchRequest<ShoppingListEntity> {
        NSFetchRequest<ShoppingListEntity>(entityName: "ShoppingList")
    }

    /// The one list the cart shows among the active lists: the general (no-store) list, else the
    /// oldest. The cart screen, Siri, the widgets and the shopping trip all pick through this
    /// rule, so a line checked or added on one surface is the line the others show.
    static func primaryList(in activeLists: [ShoppingListEntity]) -> ShoppingListEntity? {
        if let general = activeLists.first(where: { $0.store == nil }) {
            return general
        }
        return activeLists.min { lhs, rhs in
            (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
        }
    }

    /// Only the retired "completed" and "archived" values mean inactive. A missing, empty or
    /// unknown status stays active, as every shipped build (v1.2.1 included) reads it.
    var isActive: Bool {
        status != "completed" && status != "archived"
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
        ProductEntity.liveInCartOrder(products)
    }
}

extension ProductEntity {
    /// Live lines only, newest to-buy first, then the completed ones (REQ-SHELL-010).
    static func liveInCartOrder(_ products: NSSet?) -> [ProductEntity] {
        let values = (products?.allObjects as? [ProductEntity] ?? [])
            .filter { !$0.isDeletedValue }
        return values.sorted {
            if $0.isPurchasedValue != $1.isPurchasedValue {
                return !$0.isPurchasedValue && $1.isPurchasedValue
            }
            return $0.createdDate > $1.createdDate
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

    @nonobjc static func fetchRequest() -> NSFetchRequest<ProductEntity> {
        NSFetchRequest<ProductEntity>(entityName: "Product")
    }

    var displayName: String {
        name?.nilIfBlank ?? String(localized: "common.default_product")
    }

    var categoryValue: ProductCategory {
        ProductCategory.resolved(storedRawValue: category)
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

extension ProductEntity: Identifiable {}

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

    @nonobjc static func fetchRequest() -> NSFetchRequest<PurchaseHistoryEntity> {
        NSFetchRequest<PurchaseHistoryEntity>(entityName: "PurchaseHistory")
    }

    var purchaseDate: Date {
        date ?? createdAt ?? .distantPast
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
