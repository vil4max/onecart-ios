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

    /// REQ-SYNC-010: the CloudKit Production schema cannot drop a field and v1.2.1 still reads
    /// the synced records, so the model keeps every entity, attribute and relationship it has
    /// shipped, legacy ones the app no longer writes included. Adding a field updates this
    /// snapshot; removing or renaming one must fail here first.
    func test_REQ_SYNC_010_modelKeepsEveryShippedEntityAttributeAndRelationship() {
        let model = OneCartManagedObjectModel.makeModel()
        XCTAssertEqual(model.versionIdentifiers, [AnyHashable("OneCartCoreDataV9")])
        XCTAssertEqual(Set(model.entitiesByName.keys), Set(Self.shippedSchema.keys))
        for (name, snapshot) in Self.shippedSchema {
            let entity = model.entitiesByName[name]
            XCTAssertEqual(Set(entity.map { Array($0.attributesByName.keys) } ?? []), snapshot.attributes, name)
            XCTAssertEqual(
                Set(entity.map { Array($0.relationshipsByName.keys) } ?? []),
                snapshot.relationships,
                name
            )
        }
    }

    /// REQ-SYNC-010: the V9 fields are optional, so a store and CloudKit records written before
    /// V9 stay valid without them.
    func test_REQ_SYNC_010_v9ProductFieldsAreOptional() throws {
        let product = try XCTUnwrap(OneCartManagedObjectModel.makeModel().entitiesByName["Product"])
        for name in ["createdByRecordName", "purchasedByRecordName", "purchaseUpdatedAt"] {
            let attribute = try XCTUnwrap(product.attributesByName[name], name)
            XCTAssertTrue(attribute.isOptional, name)
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
        XCTAssertTrue(model.versionIdentifiers.contains(AnyHashable("OneCartCoreDataV9")))
    }

    /// REQ-CART-010: only the retired statuses hide a list, so every shipped build agrees on it.
    func test_REQ_CART_010_onlyRetiredStatusesMarkAListInactive() {
        let model = OneCartManagedObjectModel.makeModel()
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let list = ShoppingListEntity(context: context)
        for status in [nil, "", "active", "unknown"] {
            list.status = status
            XCTAssertTrue(list.isActive, "status \(status ?? "nil")")
        }
        for status in ["completed", "archived"] {
            list.status = status
            XCTAssertFalse(list.isActive, "status \(status)")
        }
    }
}

extension ManagedObjectModelTests {
    /// Every entity, attribute and relationship the model has shipped, through V9.
    static let shippedSchema: [String: (attributes: Set<String>, relationships: Set<String>)] = [
        "FamilySpace": (
            [
                "id", "name", "createdAt", "updatedAt", "deletedAt", "cachedForUserID", "serverRole",
                "needsRemoteCreation", "isHouseholdDefault",
            ],
            ["stores", "lists", "products", "historyEntries", "historyItems", "memberProfiles"]
        ),
        "Store": (
            [
                "id", "name", "icon", "colorHex", "address", "latitude", "longitude", "externalAppURL",
                "isPinned", "createdAt", "updatedAt", "deletedAt",
            ],
            ["familySpace", "lists", "products", "historyEntries"]
        ),
        "ShoppingList": (
            ["id", "title", "status", "createdAt", "updatedAt", "deletedAt"],
            ["familySpace", "store", "products"]
        ),
        "Product": (
            [
                "id", "name", "quantity", "unit", "category", "estimatedPrice", "originalPrice",
                "loyaltyPrice", "imageURL", "sourceURL", "catalogFetchedAt", "promotionEndsAt", "note",
                "isPurchased", "createdAt", "updatedAt", "purchasedAt", "purchasedByName", "createdByName",
                "deletedAt", "createdByRecordName", "purchasedByRecordName", "purchaseUpdatedAt",
            ],
            ["familySpace", "list", "store"]
        ),
        "PurchaseHistory": (
            ["id", "total", "date", "memberNames", "createdAt", "updatedAt", "deletedAt"],
            ["familySpace", "store", "items"]
        ),
        "HistoryItem": (
            [
                "id", "name", "quantity", "unit", "category", "estimatedPrice", "originalPrice", "imageURL",
                "sourceURL", "note", "purchasedAt", "purchasedByName", "createdByName", "storeName",
                "createdAt", "updatedAt", "deletedAt",
            ],
            ["familySpace", "history"]
        ),
        "MemberProfile": (
            ["id", "userRecordName", "displayName", "createdAt", "updatedAt", "deletedAt"],
            ["familySpace"]
        ),
    ]
}
