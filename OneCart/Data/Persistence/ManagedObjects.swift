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

enum ProductCategory: String, CaseIterable, Identifiable {
    case meatPoultry
    case fishSeafood
    case dairyEggs
    case grocery
    case oilCanned
    case produce
    case frozen
    case bakery
    case saucesSpices
    case alcohol
    case coldDrinks
    case hotDrinks
    case sweetsSnacks
    case babyFood
    case household
    case other

    var id: String {
        rawValue
    }

    var localizedName: String {
        switch self {
        case .meatPoultry: String(localized: "common.category.meatPoultry")
        case .fishSeafood: String(localized: "common.category.fishSeafood")
        case .dairyEggs: String(localized: "common.category.dairyEggs")
        case .grocery: String(localized: "common.category.grocery")
        case .oilCanned: String(localized: "common.category.oilCanned")
        case .produce: String(localized: "common.category.produce")
        case .frozen: String(localized: "common.category.frozen")
        case .bakery: String(localized: "common.category.bakery")
        case .saucesSpices: String(localized: "common.category.saucesSpices")
        case .alcohol: String(localized: "common.category.alcohol")
        case .coldDrinks: String(localized: "common.category.coldDrinks")
        case .hotDrinks: String(localized: "common.category.hotDrinks")
        case .sweetsSnacks: String(localized: "common.category.sweetsSnacks")
        case .babyFood: String(localized: "common.category.babyFood")
        case .household: String(localized: "common.category.household")
        case .other: String(localized: "common.category.other")
        }
    }

    var symbolName: String {
        switch self {
        case .meatPoultry: "fork.knife"
        case .fishSeafood: "fish.fill"
        case .dairyEggs: "cup.and.saucer.fill"
        case .grocery: "basket.fill"
        case .oilCanned: "shippingbox.fill"
        case .produce: "leaf.fill"
        case .frozen: "snowflake"
        case .bakery: "birthday.cake.fill"
        case .saucesSpices: "flame.fill"
        case .alcohol: "wineglass.fill"
        case .coldDrinks: "waterbottle.fill"
        case .hotDrinks: "mug.fill"
        case .sweetsSnacks: "party.popper.fill"
        case .babyFood: "stroller.fill"
        case .household: "bubbles.and.sparkles"
        case .other: "cart.fill"
        }
    }

    static func resolved(storedRawValue: String?) -> ProductCategory {
        let raw = storedRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let value = ProductCategory(rawValue: raw) {
            return value
        }
        switch raw {
        case "fresh", "produce":
            return .produce
        case "meat", "deli":
            return .meatPoultry
        case "dairy":
            return .dairyEggs
        case "drinks":
            return .coldDrinks
        default:
            return .other
        }
    }

    static func inferred(from productName: String) -> ProductCategory {
        let value = productName.lowercased()

        if value.contains("детск") || value.contains("дитяч") || value.contains("пюре")
            || value.contains("смесь") || value.contains("суміш") || value.contains("baby")
            || value.contains("infant") || value.contains("formula")
        {
            return .babyFood
        }

        if value.contains("морожен") || value.contains("мороженое") || value.contains("пельмен")
            || value.contains("вареник") || value.contains("заморож") || value.contains("наггетс")
            || value.contains("ice cream") || value.contains("frozen") || value.contains("dumpling")
            || value.contains("nugget")
        {
            return .frozen
        }

        if value.contains("конфет") || value.contains("шоколад") || value.contains("торт")
            || value.contains("печенье") || value.contains("печив") || value.contains("чипс")
            || value.contains("снек") || value.contains("снек") || value.contains("вафл")
            || value.contains("зефир") || value.contains("маршмел") || value.contains("попкорн")
            || value.contains("candy") || value.contains("chocolate") || value.contains("cookie")
            || value.contains("cake") || value.contains("chips") || value.contains("snack")
            || value.contains("cracker") || value.contains("waffle")
        {
            return .sweetsSnacks
        }

        if value.contains("хлеб") || value.contains("хліб") || value.contains("батон")
            || value.contains("булк") || value.contains("лаваш") || value.contains("выпеч")
            || value.contains("круассан") || value.contains("бублик") || value.contains("багет")
            || value.contains("bread") || value.contains("bakery") || value.contains("bagel")
            || value.contains("bun") || value.contains("pastry") || value.contains("croissant")
            || value.contains("lavash")
        {
            return .bakery
        }

        if value.contains("вино") || value.contains("пиво") || value.contains("водк")
            || value.contains("віскі") || value.contains("виски") || value.contains("коньяк")
            || value.contains("шампан") || value.contains("алкогол") || value.contains("beer")
            || value.contains("wine") || value.contains("vodka") || value.contains("whisky")
            || value.contains("whiskey") || value.contains("alcohol") || value.contains("cider")
        {
            return .alcohol
        }

        if value.contains("кава") || value.contains("кофе") || value.contains("чай")
            || value.contains("какао") || value.contains("coffee") || value.contains("tea")
            || value.contains("cocoa") || value.contains("hot chocolate")
        {
            return .hotDrinks
        }

        if value.contains("сок") || value.contains("вода") || value.contains("кола")
            || value.contains("газиров") || value.contains("лимонад") || value.contains("квас")
            || value.contains("juice") || value.contains("water") || value.contains("cola")
            || value.contains("soda") || value.contains("lemonade") || value.contains("drink")
        {
            return .coldDrinks
        }

        if value.contains("соус") || value.contains("специ") || value.contains("кетчуп")
            || value.contains("майонез") || value.contains("гірчиц") || value.contains("горчиц")
            || value.contains("приправ") || value.contains("перец") || value.contains("перець")
            || value.contains("sauce") || value.contains("spice") || value.contains("ketchup")
            || value.contains("mayo") || value.contains("mustard") || value.contains("seasoning")
        {
            return .saucesSpices
        }

        if value.contains("олі") || value.contains("олія") || value.contains("уксус")
            || value.contains("оцет") || value.contains("консерв") || value.contains("масло растит")
            || value.contains("подсолнеч") || value.contains("оливков") || value.contains("vinegar")
            || value.contains("canned") || value.contains("olive oil") || value.contains("sunflower")
        {
            return .oilCanned
        }

        if value.contains("молоко") || value.contains("йогурт") || value.contains("сыр")
            || value.contains("сир") || value.contains("кефир") || value.contains("кефір")
            || value.contains("ряженк") || value.contains("сметан") || value.contains("творог")
            || value.contains("яйц") || value.contains("яйц") || value.contains("масло сливоч")
            || value.contains("milk") || value.contains("yogurt") || value.contains("yoghurt")
            || value.contains("cheese") || value.contains("butter") || value.contains("kefir")
            || value.contains("cottage") || value.contains("sour cream") || value.contains("egg")
        {
            return .dairyEggs
        }

        if value.contains("рыб") || value.contains("риб") || value.contains("морепродукт")
            || value.contains("кревет") || value.contains("лосос") || value.contains("тунц")
            || value.contains("селед") || value.contains("оселед") || value.contains("икр")
            || value.contains("fish") || value.contains("seafood") || value.contains("shrimp")
            || value.contains("salmon") || value.contains("tuna") || value.contains("crab")
        {
            return .fishSeafood
        }

        if value.contains("мясо") || value.contains("мʼясо") || value.contains("м’ясо")
            || value.contains("курица") || value.contains("курка") || value.contains("фарш")
            || value.contains("индейк") || value.contains("говяд") || value.contains("свинин")
            || value.contains("баранин") || value.contains("колбас") || value.contains("ковбас")
            || value.contains("сосис") || value.contains("ветчин") || value.contains("бекон")
            || value.contains("стейк") || value.contains("филе") || value.contains("meat")
            || value.contains("chicken") || value.contains("beef") || value.contains("pork")
            || value.contains("turkey") || value.contains("sausage") || value.contains("ham")
            || value.contains("bacon") || value.contains("steak") || value.contains("mince")
            || value.contains("poultry")
        {
            return .meatPoultry
        }

        if value.contains("круп") || value.contains("макарон") || value.contains("мук")
            || value.contains("сахар") || value.contains("цукор") || value.contains("соль")
            || value.contains("хлопья") || value.contains("рис") || value.contains("гречк")
            || value.contains("овсян") || value.contains("каша") || value.hasPrefix("каш")
            || value.contains("pasta") || value.contains("flour") || value.contains("sugar")
            || value.contains("salt") || value.contains("cereal") || value.contains("rice")
            || value.contains("oat") || value.contains("buckwheat") || value.contains("grocery")
            || value.contains("porridge") || value.contains("grits")
        {
            return .grocery
        }

        if value.contains("яблок") || value.contains("банан") || value.contains("овощ")
            || value.contains("фрукт") || value.contains("помидор") || value.contains("огірок")
            || value.contains("томат") || value.contains("зелен") || value.contains("ягод")
            || value.contains("огурец") || value.contains("капуст") || value.contains("морков")
            || value.contains("apple") || value.contains("banana") || value.contains("tomato")
            || value.contains("fruit") || value.contains("vegetable") || value.contains("salad")
            || value.contains("cucumber") || value.contains("lemon") || value.contains("potato")
            || value.contains("onion") || value.contains("carrot") || value.contains("berry")
            || value.contains("greens") || value.contains("lettuce")
        {
            return .produce
        }

        if value.contains("мыло") || value.contains("мило") || value.contains("порошок")
            || value.contains("шампун") || value.contains("средств") || value.contains("засіб")
            || value.contains("soap") || value.contains("detergent") || value.contains("shampoo")
            || value.contains("laundry") || value.contains("cleaner") || value.contains("bleach")
        {
            return .household
        }

        // Generic "oil" after more specific oilCanned phrases
        if value.contains("oil") {
            return .oilCanned
        }

        return .other
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
