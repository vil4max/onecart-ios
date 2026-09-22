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
}
