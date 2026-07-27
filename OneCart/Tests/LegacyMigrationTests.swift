import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class LegacyMigrationTests: XCTestCase {
    func testLegacyMigrationIsIdempotentAndPreservesRelationships() async throws {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let defaults = try makeDefaults()
        let service = LegacyMigrationService(
            persistence: persistence,
            userDefaults: defaults
        )
        let data = Data(Self.legacyJSON.utf8)

        let first = try await service.migrateIfNeeded(data: data)
        let second = try await service.migrateIfNeeded(data: data)

        guard case let .migrated(familyID) = first else {
            return XCTFail("Expected migration")
        }
        XCTAssertEqual(second, .alreadyMigrated(familyID))

        let storeRequest = StoreEntity.fetchRequest()
        let listRequest = ShoppingListEntity.fetchRequest()
        let productRequest = ProductEntity.fetchRequest()
        let context = persistence.container.viewContext

        let stores = try context.fetch(storeRequest)
        let lists = try context.fetch(listRequest)
        let products = try context.fetch(productRequest)

        XCTAssertEqual(stores.count, 1)
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.list?.id, lists.first?.id)
        XCTAssertEqual(products.first?.store?.id, stores.first?.id)
        XCTAssertEqual(products.first?.familySpace?.id, familyID)
    }

    func testMigrateLegacyHouseholdDefaultsMarksKnownNames() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let legacyID = try await repository.createFamilySpace(name: "Наша семья")
        let customID = try await repository.createFamilySpace(name: "Дача")

        try await repository.migrateLegacyHouseholdDefaultsIfNeeded()

        XCTAssertTrue(
            try XCTUnwrap(repository.fetchFamilySpace(id: legacyID)).isHouseholdDefaultValue
        )
        XCTAssertFalse(
            try XCTUnwrap(repository.fetchFamilySpace(id: customID)).isHouseholdDefaultValue
        )
    }

    private static let legacyJSON = """
    {
      "version": 1,
      "savedAt": "2026-07-16T12:00:00.000Z",
      "state": {
        "users": [{"id":"user-owner","name":"Марина"}],
        "currentUserId": "user-owner",
        "stores": [{
          "id":"store-atb",
          "name":"АТБ",
          "icon":"АТБ",
          "color":"#315B9A",
          "address":null,
          "externalAppUrl":null,
          "isPinned":true
        }],
        "shoppingLists": [{
          "id":"list-atb",
          "title":"Покупки в АТБ",
          "storeId":"store-atb",
          "createdAt":"2026-07-16T11:00:00.000Z",
          "updatedAt":"2026-07-16T12:00:00.000Z",
          "status":"active"
        }],
        "products": [{
          "id":"product-bread",
          "name":"Хлеб",
          "quantity":1,
          "unit":"piece",
          "category":"other",
          "estimatedPrice":38,
          "note":"",
          "storeId":"store-atb",
          "listId":"list-atb",
          "isPurchased":false,
          "createdAt":"2026-07-16T11:30:00.000Z",
          "purchasedAt":null
        }],
        "purchaseHistory": [],
        "settings": {
          "locale":"ru",
          "theme":"system",
          "defaultUnit":"piece"
        }
      }
    }
    """
}
