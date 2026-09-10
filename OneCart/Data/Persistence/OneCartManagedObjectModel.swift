import CoreData
import Foundation

enum OneCartManagedObjectModel {
    private static let lock = NSLock()
    private static var cachedModel: NSManagedObjectModel?

    static func makeModel() -> NSManagedObjectModel {
        lock.lock()
        defer { lock.unlock() }
        if let cachedModel {
            return cachedModel
        }
        let model = buildModel()
        cachedModel = model
        return model
    }

    private static func buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["OneCartCoreDataV7"]

        let familySpace = entity("FamilySpace", FamilySpace.self)
        let store = entity("Store", StoreEntity.self)
        let list = entity("ShoppingList", ShoppingListEntity.self)
        let product = entity("Product", ProductEntity.self)
        let history = entity("PurchaseHistory", PurchaseHistoryEntity.self)
        let historyItem = entity("HistoryItem", HistoryItemEntity.self)

        let relationships = makeRelationships(
            familySpace: familySpace,
            store: store,
            list: list,
            product: product,
            history: history,
            historyItem: historyItem
        )

        familySpace.properties = makeFamilySpaceProperties(relationships)
        store.properties = makeStoreProperties(relationships)
        list.properties = makeListProperties(relationships)
        product.properties = makeProductProperties(relationships)
        history.properties = makeHistoryProperties(relationships)
        historyItem.properties = makeHistoryItemProperties(relationships)

        model.entities = [familySpace, store, list, product, history, historyItem]
        return model
    }

    // MARK: - Relationships

    private struct Relationships {
        let familyStores, storeFamily: NSRelationshipDescription
        let familyLists, listFamily: NSRelationshipDescription
        let familyProducts, productFamily: NSRelationshipDescription
        let familyHistory, historyFamily: NSRelationshipDescription
        let familyHistoryItems, historyItemFamily: NSRelationshipDescription
        let storeLists, listStore: NSRelationshipDescription
        let storeProducts, productStore: NSRelationshipDescription
        let storeHistory, historyStore: NSRelationshipDescription
        let listProducts, productList: NSRelationshipDescription
        let historyItems, itemHistory: NSRelationshipDescription
    }

    private static func makeRelationships(
        familySpace: NSEntityDescription,
        store: NSEntityDescription,
        list: NSEntityDescription,
        product: NSEntityDescription,
        history: NSEntityDescription,
        historyItem: NSEntityDescription
    ) -> Relationships {
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

        return Relationships(
            familyStores: familyStores,
            storeFamily: storeFamily,
            familyLists: familyLists,
            listFamily: listFamily,
            familyProducts: familyProducts,
            productFamily: productFamily,
            familyHistory: familyHistory,
            historyFamily: historyFamily,
            familyHistoryItems: familyHistoryItems,
            historyItemFamily: historyItemFamily,
            storeLists: storeLists,
            listStore: listStore,
            storeProducts: storeProducts,
            productStore: productStore,
            storeHistory: storeHistory,
            historyStore: historyStore,
            listProducts: listProducts,
            productList: productList,
            historyItems: historyItems,
            itemHistory: itemHistory
        )
    }

    // MARK: - Entity properties

    private static func makeFamilySpaceProperties(_ rels: Relationships) -> [NSPropertyDescription] {
        [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            attribute("cachedForUserID", .UUIDAttributeType),
            attribute("serverRole", .stringAttributeType),
            attribute("needsRemoteCreation", .booleanAttributeType),
            attribute("isHouseholdDefault", .booleanAttributeType),
            rels.familyStores,
            rels.familyLists,
            rels.familyProducts,
            rels.familyHistory,
            rels.familyHistoryItems,
        ]
    }

    private static func makeStoreProperties(_ rels: Relationships) -> [NSPropertyDescription] {
        [
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
            rels.storeFamily,
            rels.storeLists,
            rels.storeProducts,
            rels.storeHistory,
        ]
    }

    private static func makeListProperties(_ rels: Relationships) -> [NSPropertyDescription] {
        [
            attribute("id", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("status", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            rels.listFamily,
            rels.listStore,
            rels.listProducts,
        ]
    }

    private static func makeProductProperties(_ rels: Relationships) -> [NSPropertyDescription] {
        [
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
            attribute("createdByName", .stringAttributeType),
            attribute("deletedAt", .dateAttributeType),
            rels.productFamily,
            rels.productList,
            rels.productStore,
        ]
    }

    private static func makeHistoryProperties(_ rels: Relationships) -> [NSPropertyDescription] {
        [
            attribute("id", .UUIDAttributeType),
            attribute("total", .doubleAttributeType),
            attribute("date", .dateAttributeType),
            attribute("memberNames", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType),
            attribute("deletedAt", .dateAttributeType),
            rels.historyFamily,
            rels.historyStore,
            rels.historyItems,
        ]
    }

    private static func makeHistoryItemProperties(_ rels: Relationships) -> [NSPropertyDescription] {
        [
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
            rels.historyItemFamily,
            rels.itemHistory,
        ]
    }

    // MARK: - Building blocks

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
