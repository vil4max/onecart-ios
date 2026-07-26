@testable import OneCart
import CoreData
import CoreLocation
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

        _ = try await repository.addProduct(
            to: XCTUnwrap(space.activeLists.first?.id),
            draft: ProductDraft(
                name: "Хлеб",
                quantity: 1,
                unit: .piece,
                category: .other,
                estimatedPrice: 30,
                note: ""
            )
        )
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
        let (persistence, repository) = try await makeInMemoryRepository()
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
            FamilyCartMerge.isDeletableStarter(
                privateSpace,
                scope: try XCTUnwrap(persistence.scope(for: privateSpace))
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
            FamilyCartMerge.isDeletableStarter(
                shared,
                scope: try XCTUnwrap(persistence.scope(for: shared))
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
        XCTAssertTrue(
            FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault(AppSession.defaultFamilyName)
        )
        XCTAssertFalse(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Дача"))
    }

    private func makeInMemoryRepository() async throws
        -> (PersistenceController, FamilySpaceRepository)
    {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        return (persistence, repository)
    }
}
