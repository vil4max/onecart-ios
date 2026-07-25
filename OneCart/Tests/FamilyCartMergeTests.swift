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
