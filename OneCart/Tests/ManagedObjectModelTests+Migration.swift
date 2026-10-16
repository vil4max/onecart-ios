import CoreData
@testable import OneCart
import XCTest

/// Stores written by shipped models open with the current one through lightweight migration.
extension ManagedObjectModelTests {
    /// REQ-SYNC-020: a store written by 1.6.0, whose `HistoryItem` has no `createdByName`,
    /// opens with the current model through lightweight migration and keeps its archive.
    @MainActor
    func test_REQ_SYNC_020_storeWithoutHistoryCreatorOpensWithCurrentModel() throws {
        let storeURL = try makeStoreURL(prefix: "OneCartHistoryCreatorMigration")
        let itemID = UUID()

        let previous = try modelWithout(entity: "HistoryItem", attributes: ["createdByName"])
        XCTAssertNil(previous.entitiesByName["HistoryItem"]?.attributesByName["createdByName"])
        try writeStore(at: storeURL, model: previous) { context in
            let itemEntity = try XCTUnwrap(previous.entitiesByName["HistoryItem"])
            let item = NSManagedObject(entity: itemEntity, insertInto: context)
            item.setValue(itemID, forKey: "id")
            item.setValue("Bread", forKey: "name")
            item.setValue("Alex", forKey: "purchasedByName")
        }

        let current = OneCartManagedObjectModel.makeModel()
        XCTAssertNotNil(current.entitiesByName["HistoryItem"]?.attributesByName["createdByName"])
        let newContainer = try openStore(at: storeURL, model: current)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HistoryItem")
        let migrated = try newContainer.viewContext.fetch(request)
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.value(forKey: "id") as? UUID, itemID)
        XCTAssertEqual(migrated.first?.value(forKey: "name") as? String, "Bread")
        XCTAssertEqual(migrated.first?.value(forKey: "purchasedByName") as? String, "Alex")
        XCTAssertNil(migrated.first?.value(forKey: "createdByName"))
    }

    /// REQ-SYNC-010: a store written by the V8 model, whose `Product` has no author record
    /// names and no purchase version, opens with V9 and keeps its rows; the old `updatedAt`
    /// stands in as the purchase version.
    @MainActor
    func test_REQ_SYNC_010_v8StoreOpensWithTheV9ModelAndKeepsItsRows() throws {
        let storeURL = try makeStoreURL(prefix: "OneCartV8Migration")
        let productID = UUID()
        let updatedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let v9Fields: Set<String> = ["createdByRecordName", "purchasedByRecordName", "purchaseUpdatedAt"]

        let previous = try modelWithout(entity: "Product", attributes: v9Fields)
        previous.versionIdentifiers = ["OneCartCoreDataV8"]
        try writeStore(at: storeURL, model: previous) { context in
            let product = NSManagedObject(
                entity: try XCTUnwrap(previous.entitiesByName["Product"]), insertInto: context
            )
            product.setValue(productID, forKey: "id")
            product.setValue("Milk", forKey: "name")
            product.setValue(true, forKey: "isPurchased")
            product.setValue("Alex", forKey: "purchasedByName")
            product.setValue("Sam", forKey: "createdByName")
            product.setValue(updatedAt, forKey: "updatedAt")
        }

        let newContainer = try openStore(at: storeURL, model: OneCartManagedObjectModel.makeModel())

        let migrated = try newContainer.viewContext.fetch(ProductEntity.fetchRequest())
        XCTAssertEqual(migrated.count, 1)
        let product = try XCTUnwrap(migrated.first)
        XCTAssertEqual(product.id, productID)
        XCTAssertEqual(product.name, "Milk")
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedByName, "Alex")
        XCTAssertEqual(product.createdByName, "Sam")
        XCTAssertNil(product.createdByRecordName)
        XCTAssertNil(product.purchasedByRecordName)
        XCTAssertNil(product.purchaseUpdatedAt)
        XCTAssertEqual(product.purchaseVersion, updatedAt)
    }

    /// Today's model without the given attributes of one entity, mapped to plain objects so
    /// the two models never claim the same classes.
    private func modelWithout(entity name: String, attributes: Set<String>) throws -> NSManagedObjectModel {
        let model = try XCTUnwrap(OneCartManagedObjectModel.makeModel().copy() as? NSManagedObjectModel)
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            if entity.name == name {
                entity.properties = entity.properties.filter { !attributes.contains($0.name) }
            }
        }
        return model
    }

    private func makeStoreURL(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("OneCart-private.sqlite")
    }

    /// Writes rows with the given model, saves and closes the store again.
    private func writeStore(
        at url: URL,
        model: NSManagedObjectModel,
        insert: (NSManagedObjectContext) throws -> Void
    ) throws {
        let container = try openStore(at: url, model: model)
        try insert(container.viewContext)
        try container.viewContext.save()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    private func openStore(at url: URL, model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "OneCartMigration", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        return container
    }
}
