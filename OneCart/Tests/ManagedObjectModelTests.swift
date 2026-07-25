@testable import OneCart
import CoreData
import CoreLocation
import XCTest

final class ManagedObjectModelTests: XCTestCase {
    func testManagedObjectModelHasOfflineSyncRelationshipsAndTimestamps() {
        let model = OneCartManagedObjectModel.makeModel()
        XCTAssertEqual(model.entities.count, 6)

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
        for name in ["FamilySpace", "Store", "ShoppingList", "Product", "PurchaseHistory", "HistoryItem"] {
            XCTAssertNotNil(model.entitiesByName[name]?.attributesByName["deletedAt"])
        }
    }
}
