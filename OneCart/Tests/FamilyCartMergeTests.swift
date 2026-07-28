import CoreData
@testable import OneCart
import XCTest

final class FamilyCartMergeTests: XCTestCase {
    func testDeletableStarterFamilyDetection() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(
            name: AppModel.defaultFamilyName,
            isHouseholdDefault: true
        )
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let scope = try XCTUnwrap(persistence.scope(for: space))
        XCTAssertTrue(
            FamilyCartMerge.isDeletableStarter(
                space,
                scope: scope
            )
        )

        let listID = try XCTUnwrap(space.activeLists.first?.id)
        _ = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Хлеб",
                quantity: 1,
                unit: .piece,
                category: .other,
                estimatedPrice: 30,
                note: ""
            )
        )
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let updated = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let updatedScope = try XCTUnwrap(persistence.scope(for: updated))
        XCTAssertFalse(
            FamilyCartMerge.isDeletableStarter(
                updated,
                scope: updatedScope
            )
        )
    }

    func testMergeFamilyContentCopiesProducts() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let sourceID = try await repository.createFamilySpace(name: "Моя")
        let destinationID = try await repository.createFamilySpace(name: "Семейная")
        let source = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID))
        let listID = try XCTUnwrap(source.activeLists.first?.id)
        _ = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Молоко",
                quantity: 2,
                unit: .piece,
                category: .other,
                estimatedPrice: 55,
                note: ""
            )
        )

        try await repository.mergeFamilyContent(from: sourceID, into: destinationID)

        let destination = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        XCTAssertEqual(destination.sortedProducts.count, 1)
        XCTAssertEqual(destination.sortedProducts.first?.displayName, "Молоко")
        XCTAssertNil(try repository.fetchFamilySpace(id: sourceID))
    }

    func testDefaultFamilyNameIsStable() {
        let expected = String(localized: String.LocalizationValue("cart.default_title"))
        XCTAssertEqual(AppModel.defaultFamilyName, expected)
        XCTAssertFalse(AppModel.defaultFamilyName.isEmpty)
    }

    func testSharedOrNonDefaultCartIsNotDeletableStarter() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let privateNonDefault = try await repository.createFamilySpace(
            name: AppModel.defaultFamilyName,
            isHouseholdDefault: false
        )
        let privateSpace = try XCTUnwrap(repository.fetchFamilySpace(id: privateNonDefault))
        XCTAssertFalse(
            try FamilyCartMerge.isDeletableStarter(
                privateSpace,
                scope: XCTUnwrap(persistence.scope(for: privateSpace))
            )
        )

        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = AppModel.defaultFamilyName
            space.createdAt = Date()
            space.updatedAt = Date()
            space.isHouseholdDefault = NSNumber(value: true)
        }
        let shared = try XCTUnwrap(repository.fetchFamilySpace(id: sharedID))
        XCTAssertFalse(
            try FamilyCartMerge.isDeletableStarter(
                shared,
                scope: XCTUnwrap(persistence.scope(for: shared))
            )
        )
    }

    func testContentSummaryAndLegacyNameMigrationRules() {
        XCTAssertTrue(
            FamilySpaceContentSummary(productCount: 0, storeCount: 0, historyCount: 0).isEmpty
        )
        XCTAssertFalse(
            FamilySpaceContentSummary(productCount: 1, storeCount: 0, historyCount: 0).isEmpty
        )
        XCTAssertTrue(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Наша семья"))
        XCTAssertTrue(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Наша группа"))
        XCTAssertTrue(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Наши покупки"))
        XCTAssertTrue(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Our shopping"))
        XCTAssertTrue(
            FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault(AppSession.defaultFamilyName)
        )
        XCTAssertFalse(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Дача"))
    }

    func testMergeFamilyContentRejectsSharedSource() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let destinationID = try await repository.createFamilySpace(name: "Семейная")
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Чужая"
            space.createdAt = Date()
            space.updatedAt = Date()
            let list = ShoppingListEntity(context: context)
            try persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = UUID()
            list.title = "Общий список"
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = Date()
            list.updatedAt = Date()
            list.familySpace = space
        }

        do {
            try await repository.mergeFamilyContent(from: sharedID, into: destinationID)
            XCTFail("Expected crossShareRelationship")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .crossShareRelationship)
        }
    }

    func testMergeFamilyContentRequiresDestinationPermission() async throws {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let owner = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let sourceID = try await owner.createFamilySpace(name: "Моя")
        let destinationID = try await owner.createFamilySpace(name: "Семейная")
        let denied = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: DenyAllPermissionAuthorizer()
        )

        do {
            try await denied.mergeFamilyContent(from: sourceID, into: destinationID)
            XCTFail("Expected permissionDenied")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }
    }
}
