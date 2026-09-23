import CoreData
@testable import OneCart
import XCTest

final class ManagedObjectModelTests: XCTestCase {
    func testManagedObjectModelHasOfflineSyncRelationshipsAndTimestamps() {
        let model = OneCartManagedObjectModel.makeModel()
        XCTAssertEqual(model.entities.count, 7)

        for entity in model.entities {
            XCTAssertTrue(
                entity.uniquenessConstraints.isEmpty,
                "CloudKit does not support unique constraints on \(entity.name ?? "Entity")"
            )
            for relationship in entity.relationshipsByName.values {
                XCTAssertTrue(relationship.isOptional)
                XCTAssertNotNil(
                    relationship.inverseRelationship,
                    "\(entity.name ?? "Entity").\(relationship.name) needs an inverse"
                )
                XCTAssertFalse(relationship.isOrdered)
            }
        }

        XCTAssertNotNil(model.entitiesByName["FamilySpace"]?.attributesByName["cachedForUserID"])
        XCTAssertNotNil(model.entitiesByName["FamilySpace"]?.attributesByName["isHouseholdDefault"])
        let entityNames = [
            "FamilySpace", "Store", "ShoppingList", "Product", "PurchaseHistory", "HistoryItem", "MemberProfile",
        ]
        for name in entityNames {
            XCTAssertNotNil(model.entitiesByName[name]?.attributesByName["deletedAt"])
        }
    }

    /// REQ-AUTH-040: the member profile is CloudKit-compatible and belongs to the cart, so it
    /// lands in the cart's zone and every member can read it.
    func test_REQ_AUTH_040_memberProfileBelongsToTheCartWithOptionalFields() throws {
        let model = OneCartManagedObjectModel.makeModel()
        let profile = try XCTUnwrap(model.entitiesByName["MemberProfile"])
        for name in ["id", "userRecordName", "displayName", "createdAt", "updatedAt", "deletedAt"] {
            let attribute = try XCTUnwrap(profile.attributesByName[name], name)
            XCTAssertTrue(attribute.isOptional, name)
        }
        let family = try XCTUnwrap(profile.relationshipsByName["familySpace"])
        XCTAssertEqual(family.destinationEntity?.name, "FamilySpace")
        XCTAssertEqual(family.inverseRelationship?.name, "memberProfiles")
        XCTAssertTrue(model.versionIdentifiers.contains(AnyHashable("OneCartCoreDataV8")))
    }

    /// REQ-SYNC-020: a store written by 1.6.0, whose `HistoryItem` has no `createdByName`,
    /// opens with the current model through lightweight migration and keeps its archive.
    @MainActor
    func test_REQ_SYNC_020_storeWithoutHistoryCreatorOpensWithCurrentModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartHistoryCreatorMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("OneCart-private.sqlite")
        let itemID = UUID()

        let previous = try Self.modelWithoutHistoryCreator()
        XCTAssertNil(previous.entitiesByName["HistoryItem"]?.attributesByName["createdByName"])
        let oldContainer = NSPersistentContainer(name: "OneCartPrevious", managedObjectModel: previous)
        oldContainer.persistentStoreDescriptions = [Self.migratingDescription(for: storeURL)]
        try Self.loadStores(of: oldContainer)
        let oldContext = oldContainer.viewContext
        let itemEntity = try XCTUnwrap(previous.entitiesByName["HistoryItem"])
        let item = NSManagedObject(entity: itemEntity, insertInto: oldContext)
        item.setValue(itemID, forKey: "id")
        item.setValue("Bread", forKey: "name")
        item.setValue("Alex", forKey: "purchasedByName")
        try oldContext.save()
        for store in oldContainer.persistentStoreCoordinator.persistentStores {
            try oldContainer.persistentStoreCoordinator.remove(store)
        }

        let current = OneCartManagedObjectModel.makeModel()
        XCTAssertNotNil(current.entitiesByName["HistoryItem"]?.attributesByName["createdByName"])
        let newContainer = NSPersistentContainer(name: "OneCartCurrent", managedObjectModel: current)
        newContainer.persistentStoreDescriptions = [Self.migratingDescription(for: storeURL)]
        try Self.loadStores(of: newContainer)

        let request = NSFetchRequest<NSManagedObject>(entityName: "HistoryItem")
        let migrated = try newContainer.viewContext.fetch(request)
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.value(forKey: "id") as? UUID, itemID)
        XCTAssertEqual(migrated.first?.value(forKey: "name") as? String, "Bread")
        XCTAssertEqual(migrated.first?.value(forKey: "purchasedByName") as? String, "Alex")
        XCTAssertNil(migrated.first?.value(forKey: "createdByName"))
    }

    /// The 1.6.0 model: today's model without `HistoryItem.createdByName`, mapped to plain
    /// objects so the two models never claim the same classes.
    private static func modelWithoutHistoryCreator() throws -> NSManagedObjectModel {
        let model = try XCTUnwrap(OneCartManagedObjectModel.makeModel().copy() as? NSManagedObjectModel)
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            if entity.name == "HistoryItem" {
                entity.properties = entity.properties.filter { $0.name != "createdByName" }
            }
        }
        return model
    }

    private static func migratingDescription(for url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    private static func loadStores(of container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
    }
}
