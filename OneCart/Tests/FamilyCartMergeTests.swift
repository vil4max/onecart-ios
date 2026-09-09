import CoreData
@testable import OneCart
import XCTest

@MainActor
final class FamilyCartMergeTests: XCTestCase {
    func testDeletableStarterFamilyDetection() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(
            name: AppSession.defaultFamilyName,
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

    func testMergeFamilyContentKeepsSourceWhenArchiveDisabled() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let sourceID = try await repository.createFamilySpace(name: "Моя")
        let destinationID = try await repository.createFamilySpace(name: "Семейная")
        let source = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID))
        let listID = try XCTUnwrap(source.activeLists.first?.id)
        _ = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Хлеб",
                quantity: 1,
                unit: .piece,
                category: .other,
                estimatedPrice: 0,
                note: ""
            )
        )

        try await repository.mergeFamilyContent(
            from: sourceID,
            into: destinationID,
            archiveSource: false
        )

        XCTAssertNotNil(try repository.fetchFamilySpace(id: sourceID))
        let destination = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        XCTAssertEqual(destination.sortedProducts.map(\.displayName), ["Хлеб"])
    }

    func testMergeFamilyContentLWWSameNormalizedName() async throws {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let sourceID = try await repository.createFamilySpace(name: "Моя")
        let destinationID = try await repository.createFamilySpace(name: "Семейная")
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)

        try await persistence.performBackgroundTask { context in
            let destination = try FamilySpaceRepository.requireFamilySpace(id: destinationID, in: context)
            guard let list = destination.activeLists.first else {
                throw RepositoryError.listNotFound
            }
            let product = ProductEntity(context: context)
            try persistence.assign(product, toSameStoreAs: destination, in: context)
            product.id = UUID()
            product.name = "Молоко"
            product.quantity = NSNumber(value: 1)
            product.unit = ProductUnit.piece.rawValue
            product.category = ProductCategory.other.rawValue
            product.estimatedPrice = NSNumber(value: 0)
            product.isPurchased = NSNumber(value: false)
            product.note = "old"
            product.createdAt = older
            product.updatedAt = older
            product.familySpace = destination
            product.list = list
        }

        try await persistence.performBackgroundTask { context in
            let source = try FamilySpaceRepository.requireFamilySpace(id: sourceID, in: context)
            guard let list = source.activeLists.first else {
                throw RepositoryError.listNotFound
            }
            let product = ProductEntity(context: context)
            try persistence.assign(product, toSameStoreAs: source, in: context)
            product.id = UUID()
            product.name = " молоко "
            product.quantity = NSNumber(value: 3)
            product.unit = ProductUnit.piece.rawValue
            product.category = ProductCategory.other.rawValue
            product.estimatedPrice = NSNumber(value: 0)
            product.isPurchased = NSNumber(value: true)
            product.note = "new"
            product.createdAt = newer
            product.updatedAt = newer
            product.familySpace = source
            product.list = list
        }

        try await repository.mergeFamilyContent(
            from: sourceID,
            into: destinationID,
            archiveSource: false
        )

        let destination = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        XCTAssertEqual(destination.sortedProducts.count, 1)
        let merged = try XCTUnwrap(destination.sortedProducts.first)
        XCTAssertEqual(merged.noteValue, "new")
        XCTAssertEqual(merged.quantityValue, 3)
        XCTAssertTrue(merged.isPurchasedValue)
    }

    func testNormalizedNameAndLWWHelpers() {
        XCTAssertEqual(
            FamilyCartMerge.normalizedProductName("  Молоко "),
            FamilyCartMerge.normalizedProductName("молоко")
        )
        XCTAssertTrue(
            FamilyCartMerge.shouldPreferSourceProduct(
                sourceUpdatedAt: Date(timeIntervalSince1970: 2),
                destinationUpdatedAt: Date(timeIntervalSince1970: 1)
            )
        )
        XCTAssertFalse(
            FamilyCartMerge.shouldPreferSourceProduct(
                sourceUpdatedAt: Date(timeIntervalSince1970: 1),
                destinationUpdatedAt: Date(timeIntervalSince1970: 2)
            )
        )
    }

    func testDefaultFamilyNameIsStable() {
        let expected = String(localized: String.LocalizationValue("cart.default_title"))
        XCTAssertEqual(AppSession.defaultFamilyName, expected)
        XCTAssertFalse(AppSession.defaultFamilyName.isEmpty)
    }

    func testSharedOrNonDefaultCartIsNotDeletableStarter() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let privateNonDefault = try await repository.createFamilySpace(
            name: AppSession.defaultFamilyName,
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
            space.name = AppSession.defaultFamilyName
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
        XCTAssertTrue(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Shopping list"))
        XCTAssertTrue(FamilyCartMerge.shouldMigrateLegacyNameToHouseholdDefault("Список покупок"))
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

@MainActor
final class PersonalCartContentRestoreTests: XCTestCase {
    func testRestoreKeepsStableIDsHistoryAndSourceGraphAcrossRetries() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let accountID = UUID()
        let sourceID = try await repository.createFamilySpace(name: "Local", cachedForUserID: accountID)
        let destinationID = try await repository.createFamilySpace(name: "Existing", cachedForUserID: accountID)
        let source = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID))
        let destination = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        let sourceListID = try XCTUnwrap(source.activeLists.first?.id)
        let destinationListID = try XCTUnwrap(destination.activeLists.first?.id)
        let firstID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Bread"))
        let secondID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Bread"))
        let historyProductID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Eggs"))
        try await repository.togglePurchased(id: historyProductID, participantDisplayName: "Shopper")
        let historyResult = try await repository.completePurchased(listID: sourceListID)
        let historyID = try XCTUnwrap(historyResult)
        let completedID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Milk"))
        try await repository.togglePurchased(id: completedID, participantDisplayName: "Shopper")
        let remoteID = try await repository.addProduct(to: destinationListID, draft: productDraft(name: "Bread"))

        for _ in 0 ..< 2 {
            let restored = try await repository.restoreProvisionalPersonalContent(
                from: sourceID, into: destinationID, accountID: accountID
            )
            XCTAssertTrue(restored)
        }
        await persistence.container.viewContext.perform { persistence.container.viewContext.processPendingChanges() }
        let restored = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        XCTAssertEqual(Set(restored.sortedProducts.compactMap(\.id)), [firstID, secondID, completedID, remoteID])
        XCTAssertEqual(restored.sortedProducts.filter { $0.displayName == "Bread" }.count, 3)
        XCTAssertTrue(restored.sortedProducts.first { $0.id == completedID }?.isPurchasedValue == true)
        XCTAssertEqual(restored.sortedProducts.first { $0.id == completedID }?.purchasedByName, "Shopper")
        XCTAssertEqual(restored.sortedHistory.map(\.id), [historyID])
        XCTAssertEqual(restored.sortedHistory.first?.sortedItems.map(\.id), [historyProductID])
        XCTAssertEqual(restored.sortedHistory.first?.sortedItems.first?.purchasedByName, "Shopper")
        XCTAssertEqual(restored.sortedHistory.first?.familySpace?.id, destinationID)
        let original = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID))
        XCTAssertEqual(Set(original.sortedProducts.compactMap(\.id)), [firstID, secondID, completedID])
        XCTAssertEqual(original.sortedHistory.first?.id, historyID)
        XCTAssertNil(original.deletedAt)

        try await repository.updateProduct(id: firstID, familySpaceID: destinationID,
                                           draft: productDraft(name: "Destination edit"))
        await persistence.container.viewContext.perform { persistence.container.viewContext.processPendingChanges() }
        XCTAssertEqual(try repository.fetchFamilySpace(id: destinationID)?.sortedProducts.first { $0.id == firstID }?
            .displayName, "Destination edit")
        XCTAssertEqual(try repository.fetchFamilySpace(id: sourceID)?.sortedProducts.first { $0.id == firstID }?
            .displayName, "Bread")
        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "familySpace.id == %@ AND id == %@", destinationID as NSUUID,
                                        historyProductID as NSUUID)
        XCTAssertNotNil(try persistence.container.viewContext.fetch(request).first?.deletedAt)
    }

    func testRestorePreservesDestinationTombstoneAndOtherAccountBoundary() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let accountID = UUID()
        let sourceID = try await repository.createFamilySpace(name: "Local", cachedForUserID: accountID)
        let destinationID = try await repository.createFamilySpace(name: "Existing", cachedForUserID: accountID)
        let sourceListID = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID)?.activeLists.first?.id)
        let destinationListID = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID)?.activeLists.first?.id)
        let productID = try await repository.addProduct(to: sourceListID, draft: productDraft(name: "Bread"))
        _ = try await repository.addProduct(to: destinationListID, id: productID, draft: productDraft(name: "Deleted"))
        try await repository.deleteProduct(id: productID, familySpaceID: destinationID)

        do {
            _ = try await repository.restoreProvisionalPersonalContent(
                from: sourceID, into: destinationID, accountID: UUID()
            )
            XCTFail("Expected permissionDenied")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }
        let restored = try await repository.restoreProvisionalPersonalContent(
            from: sourceID, into: destinationID, accountID: accountID
        )
        await persistence.container.viewContext.perform { persistence.container.viewContext.processPendingChanges() }

        XCTAssertTrue(restored)
        XCTAssertTrue(try XCTUnwrap(repository.fetchFamilySpace(id: destinationID)).sortedProducts.isEmpty)
        XCTAssertEqual(try repository.fetchFamilySpace(id: sourceID)?.sortedProducts.first?.id, productID)
        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "familySpace.id == %@", destinationID as NSUUID)
        let products = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(products.count, 1)
        XCTAssertNotNil(products.first?.deletedAt)
        XCTAssertEqual(products.first?.name, "Deleted")
    }
}
