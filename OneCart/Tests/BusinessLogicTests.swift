import CloudKit
import CoreData
@testable import OneCart
import XCTest

/// Covers repository cart lifecycle, merge/claim/archive, CloudKit helpers, and Core Data classifiers
/// that are not exercised by the broader OneCartTests / FamilyCartMergeTests suites.
final class BusinessLogicTests: XCTestCase {
    // MARK: - Cart lifecycle

    func testTogglePurchasedSetsAndClearsBuyer() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (_, listID, productID) = try await seedCart(repository: repository)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        var product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedByName, "Анна")
        XCTAssertNotNil(product.purchasedAt)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertFalse(product.isPurchasedValue)
        XCTAssertNil(product.purchasedByName)
        XCTAssertNil(product.purchasedAt)
        _ = listID
    }

    func testUpdateProductRewritesFields() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (_, _, productID) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Молоко", quantity: 1, price: 40)
        )

        try await repository.updateProduct(
            id: productID,
            draft: productDraft(name: "Молоко 2.5%", quantity: 2, price: 55, note: "холодное")
        )

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(product.displayName, "Молоко 2.5%")
        XCTAssertEqual(product.quantityValue, 2, accuracy: 0.001)
        XCTAssertEqual(product.estimatedPriceValue, 55, accuracy: 0.001)
        XCTAssertEqual(product.note, "холодное")
    }

    func testMoveProductTransfersToDestinationListInSameFamily() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (familyID, sourceListID, productID) = try await seedCart(repository: repository)
        let destinationListID = try await repository.addList(
            to: familyID,
            title: "АТБ"
        )

        try await repository.moveProduct(id: productID, to: destinationListID)

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(product.list?.id, destinationListID)
        XCTAssertNotEqual(product.list?.id, sourceListID)
    }

    func testMoveProductRejectsCrossFamilyDestination() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (_, _, productID) = try await seedCart(repository: repository)
        let otherFamilyID = try await repository.createFamilySpace(name: "Другая")
        let otherListID = try XCTUnwrap(
            repository.fetchFamilySpace(id: otherFamilyID)?.activeLists.first?.id
        )

        do {
            try await repository.moveProduct(id: productID, to: otherListID)
            XCTFail("Expected crossShareRelationship")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .crossShareRelationship)
        }
    }

    func testCompleteListArchivesProductsCreatesHistoryAndReplacementList() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(
            repository: repository,
            draft: productDraft(name: "Хлеб", quantity: 1, price: 38)
        )
        _ = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Молоко", quantity: 1, price: 42)
        )
        try await repository.togglePurchased(
            id: try XCTUnwrap(
                repository.fetchFamilySpace(id: familyID)?.sortedProducts.first?.id
            ),
            participantDisplayName: "Игорь"
        )

        let historyID = try await repository.completeList(id: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedProducts.isEmpty)
        XCTAssertEqual(space.activeLists.count, 1)
        XCTAssertNotEqual(space.activeLists.first?.id, listID)
        XCTAssertEqual(space.activeLists.first?.displayTitle, "Общий список")
        XCTAssertEqual(space.sortedHistory.count, 1)
        XCTAssertEqual(space.sortedHistory.first?.id, historyID)
        XCTAssertEqual(space.sortedHistory.first?.total?.doubleValue ?? 0, 80, accuracy: 0.001)
        XCTAssertTrue(space.sortedHistory.first?.memberNames?.contains("Игорь") == true)

        let completedRequest = ShoppingListEntity.fetchRequest()
        completedRequest.predicate = NSPredicate(format: "id == %@", listID as NSUUID)
        let completed = try XCTUnwrap(
            persistence.container.viewContext.fetch(completedRequest).first
        )
        XCTAssertEqual(completed.statusValue, .completed)
    }

    func testDeleteHistorySoftDeletesEntryAndItems() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(repository: repository)
        let historyID = try await repository.completeList(id: listID)

        try await repository.deleteHistory(id: historyID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedHistory.isEmpty)

        let request = PurchaseHistoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", historyID as NSUUID)
        let stored = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        XCTAssertNotNil(stored.deletedAt)
        let items = stored.items?.allObjects as? [HistoryItemEntity] ?? []
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.deletedAt != nil })
    }

    func testRefreshCatalogPricesUpdatesMatchingSourceURL() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (_, listID, productID) = try await seedCart(
            repository: repository,
            draft: ProductDraft(
                name: "Молоко",
                quantity: 1,
                unit: .piece,
                category: .dairy,
                estimatedPrice: 40,
                note: "",
                sourceURL: "https://shop.example.com/milk?utm=1"
            )
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_721_280_000)

        let updated = try await repository.refreshCatalogPrices(
            in: listID,
            snapshots: [
                CatalogPriceSnapshot(
                    sourceURL: "https://shop.example.com/milk",
                    price: 49.9,
                    originalPrice: 69.9,
                    loyaltyPrice: 44.9,
                    fetchedAt: fetchedAt,
                    promotionEndsAt: fetchedAt.addingTimeInterval(86_400)
                ),
            ]
        )

        XCTAssertEqual(updated, 1)
        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(product.estimatedPriceValue, 49.9, accuracy: 0.001)
        XCTAssertEqual(product.originalPrice?.doubleValue ?? 0, 69.9, accuracy: 0.001)
        XCTAssertEqual(product.loyaltyPrice?.doubleValue ?? 0, 44.9, accuracy: 0.001)
        XCTAssertEqual(product.catalogFetchedAt, fetchedAt)
    }

    func testRefreshCatalogPricesIgnoresStaleSnapshot() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let fetchedAt = Date(timeIntervalSince1970: 1_721_280_000)
        let (_, listID, productID) = try await seedCart(
            repository: repository,
            draft: ProductDraft(
                name: "Молоко",
                quantity: 1,
                unit: .piece,
                category: .dairy,
                estimatedPrice: 40,
                note: "",
                sourceURL: "https://shop.example.com/milk",
                catalogFetchedAt: fetchedAt
            )
        )

        let updated = try await repository.refreshCatalogPrices(
            in: listID,
            snapshots: [
                CatalogPriceSnapshot(
                    sourceURL: "https://shop.example.com/milk",
                    price: 99,
                    originalPrice: nil,
                    loyaltyPrice: nil,
                    fetchedAt: fetchedAt.addingTimeInterval(-60),
                    promotionEndsAt: nil
                ),
            ]
        )

        XCTAssertEqual(updated, 0)
        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(product.estimatedPriceValue, 40, accuracy: 0.001)
    }

    func testCatalogPriceSnapshotStripsQueryAndFragment() {
        XCTAssertEqual(
            CatalogPriceSnapshot.canonicalSourceURL(
                from: "https://shop.example.com/item?x=1#frag"
            ),
            "https://shop.example.com/item"
        )
    }

    func testAddProductIsIdempotentForExactStableID() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (familyID, listID, _) = try await seedCart(repository: repository, name: "Семья")
        let stableID = UUID()

        let first = try await repository.addProduct(
            to: listID,
            id: stableID,
            draft: productDraft(name: "Яйца")
        )
        let second = try await repository.addProduct(
            to: listID,
            id: stableID,
            draft: productDraft(name: "Яйца другие")
        )

        XCTAssertEqual(first, stableID)
        XCTAssertEqual(second, stableID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.sortedProducts.filter { $0.id == stableID }.count, 1)
        XCTAssertEqual(
            space.sortedProducts.first { $0.id == stableID }?.displayName,
            "Яйца"
        )
    }

    func testInvalidNamesAreRejected() async throws {
        let (_, repository) = try await makeInMemoryRepository()

        do {
            _ = try await repository.createFamilySpace(name: "   ")
            XCTFail("Expected invalidName")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidName)
        }

        let familyID = try await repository.createFamilySpace(name: "OK")
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )

        do {
            _ = try await repository.addProduct(
                to: listID,
                draft: productDraft(name: " \n\t ")
            )
            XCTFail("Expected invalidName")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidName)
        }

        do {
            try await repository.renameFamilySpace(id: familyID, name: " ")
            XCTFail("Expected invalidName")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .invalidName)
        }
    }

    func testRenameFamilySpaceUpdatesDisplayName() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Старое")
        try await repository.renameFamilySpace(id: familyID, name: "  Новое имя  ")
        XCTAssertEqual(
            repository.fetchFamilySpace(id: familyID)?.displayName,
            "Новое имя"
        )
    }

    // MARK: - Claim / archive / merge / dedupe

    func testClaimUnassignedFamilySpacesStampsPrivateOnly() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let privateID = try await repository.createFamilySpace(name: "Личная")
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Общая"
            space.createdAt = Date()
            space.updatedAt = Date()
        }

        let userID = UUID()
        try await repository.claimUnassignedFamilySpaces(for: userID)

        let privateSpace = try XCTUnwrap(repository.fetchFamilySpace(id: privateID))
        XCTAssertEqual(privateSpace.cachedForUserID, userID)
        XCTAssertEqual(privateSpace.serverRole, "owner")

        let sharedRequest = FamilySpace.fetchRequest()
        sharedRequest.predicate = NSPredicate(format: "id == %@", sharedID as NSUUID)
        let shared = try XCTUnwrap(
            persistence.container.viewContext.fetch(sharedRequest).first
        )
        XCTAssertNil(shared.cachedForUserID)
    }

    func testArchiveFamilySpaceHidesCartAndSoftDeletesChildren() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, _, productID) = try await seedCart(repository: repository)
        _ = try await repository.addStore(
            to: familyID,
            draft: StoreDraft(
                name: "АТБ",
                icon: "АТБ",
                colorHex: "#E30613",
                address: nil,
                externalAppURL: nil,
                isPinned: false
            )
        )

        try await repository.archiveFamilySpace(id: familyID)

        XCTAssertNil(try repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(try repository.fetchFamilySpaces().isEmpty)

        let productRequest = ProductEntity.fetchRequest()
        productRequest.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let product = try XCTUnwrap(
            persistence.container.viewContext.fetch(productRequest).first
        )
        XCTAssertNotNil(product.deletedAt)

        let spaceRequest = FamilySpace.fetchRequest()
        spaceRequest.predicate = NSPredicate(format: "id == %@", familyID as NSUUID)
        let space = try XCTUnwrap(persistence.container.viewContext.fetch(spaceRequest).first)
        XCTAssertNotNil(space.deletedAt)
        let stores = space.stores?.allObjects as? [StoreEntity] ?? []
        XCTAssertTrue(stores.allSatisfy { $0.deletedAt != nil })
    }

    func testMergeFamilyContentRemapsStoresOntoDestination() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let sourceID = try await repository.createFamilySpace(name: "Моя")
        let destinationID = try await repository.createFamilySpace(name: "Семейная")
        let storeID = try await repository.addStore(
            to: sourceID,
            draft: StoreDraft(
                name: "Сільпо",
                icon: "С",
                colorHex: "#34785B",
                address: "Київ",
                latitude: 50.45,
                longitude: 30.52,
                externalAppURL: nil,
                isPinned: true
            )
        )
        let source = try XCTUnwrap(repository.fetchFamilySpace(id: sourceID))
        let listID = try XCTUnwrap(source.activeLists.first?.id)
        let productID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Йогурт", price: 28)
        )
        try await assignStore(
            persistence: persistence,
            productID: productID,
            storeID: storeID
        )

        try await repository.mergeFamilyContent(from: sourceID, into: destinationID)

        let destination = try XCTUnwrap(repository.fetchFamilySpace(id: destinationID))
        XCTAssertEqual(destination.sortedProducts.count, 1)
        XCTAssertEqual(destination.sortedProducts.first?.displayName, "Йогурт")
        XCTAssertEqual(destination.sortedProducts.first?.store?.displayName, "Сільпо")
        XCTAssertNotEqual(destination.sortedProducts.first?.store?.id, storeID)
        XCTAssertEqual(destination.sortedStores.filter { $0.displayName == "Сільпо" }.count, 1)
        XCTAssertNil(try repository.fetchFamilySpace(id: sourceID))
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

    func testDeduplicateStableIDsKeepsNewerProduct() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Семья")
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(space.activeLists.first?.id)
        let stableID = UUID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        try await persistence.performBackgroundTask { context in
            guard let family = try Self.fetchFamilySpace(id: familyID, in: context),
                  let list = try Self.fetchList(id: listID, in: context)
            else {
                throw RepositoryError.familySpaceNotFound
            }

            let first = ProductEntity(context: context)
            try persistence.assign(first, toSameStoreAs: family, in: context)
            first.id = stableID
            first.name = "Старый"
            first.quantity = NSNumber(value: 1)
            first.unit = ProductUnit.piece.rawValue
            first.category = ProductCategory.other.rawValue
            first.estimatedPrice = NSNumber(value: 10)
            first.note = ""
            first.isPurchased = NSNumber(value: false)
            first.createdAt = older
            first.updatedAt = older
            first.familySpace = family
            first.list = list

            let second = ProductEntity(context: context)
            try persistence.assign(second, toSameStoreAs: family, in: context)
            second.id = stableID
            second.name = "Новый"
            second.quantity = NSNumber(value: 1)
            second.unit = ProductUnit.piece.rawValue
            second.category = ProductCategory.other.rawValue
            second.estimatedPrice = NSNumber(value: 10)
            second.note = ""
            second.isPurchased = NSNumber(value: false)
            second.createdAt = newer
            second.updatedAt = newer
            second.familySpace = family
            second.list = list
        }

        try await repository.deduplicateStableIDs()
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND deletedAt == nil",
            stableID as NSUUID
        )
        let alive = try persistence.container.viewContext.fetch(request)
        XCTAssertEqual(alive.count, 1)
        XCTAssertEqual(alive.first?.displayName, "Новый")

        let tombstones = try persistence.container.viewContext.fetch(ProductEntity.fetchRequest())
            .filter { $0.id == stableID && $0.deletedAt != nil }
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.displayName, "Старый")
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

    func testAssociateAndRemoveCachedFamilySpace() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let userID = UUID()
        let familyID = try await repository.createFamilySpace(name: "Кэш")

        try await repository.associateFamilySpace(
            id: familyID,
            with: userID,
            role: FamilyAccess.owner.rawValue,
            needsRemoteCreation: true
        )
        var space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(space.cachedForUserID, userID)
        XCTAssertEqual(space.serverRole, FamilyAccess.owner.rawValue)
        XCTAssertEqual(space.needsRemoteCreation?.boolValue, true)

        try await repository.removeCachedFamilySpace(id: familyID, for: userID)
        XCTAssertNil(try repository.fetchFamilySpace(id: familyID))
    }

    func testSoftDeleteStoreUnlinksProducts() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, productID) = try await seedCart(repository: repository)
        let storeID = try await repository.addStore(
            to: familyID,
            draft: StoreDraft(
                name: "АТБ",
                icon: "АТБ",
                colorHex: "#E30613",
                address: nil,
                externalAppURL: nil,
                isPinned: false
            )
        )
        try await assignStore(
            persistence: persistence,
            productID: productID,
            storeID: storeID
        )
        XCTAssertEqual(fetchProduct(id: productID, repository: repository)?.store?.id, storeID)

        try await repository.deleteStore(id: storeID)

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertNil(product.store)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(space.sortedStores.isEmpty)
        _ = listID
    }

    // MARK: - CloudKit / persistence classifiers

    func testCloudKitBackendAccessAndInMemoryRestoredAccount() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let backend = CloudKitBackendService(persistence: persistence)
        let privateID = try await repository.createFamilySpace(name: "Моя")
        let privateSpace = try XCTUnwrap(repository.fetchFamilySpace(id: privateID))
        XCTAssertEqual(backend.access(for: privateSpace), .owner)

        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Общая"
            space.createdAt = Date()
            space.updatedAt = Date()
        }
        let sharedSpace = try XCTUnwrap(repository.fetchFamilySpace(id: sharedID))
        XCTAssertEqual(backend.access(for: sharedSpace), .member)

        let account = try await backend.restoredAccount(
            appleUserID: "apple-user",
            displayName: "  "
        )
        XCTAssertEqual(account.id, OneCartStableID.uuid(for: "onecart.in-memory-user"))
        XCTAssertEqual(account.displayName, "Пользователь")
    }

    func testCloudKitUserFacingErrorMapsAuthAndPermission() {
        let auth = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.notAuthenticated.rawValue,
            userInfo: nil
        )
        XCTAssertTrue(
            CloudKitUserFacingError.message(for: auth).contains("Apple Account")
        )

        let permission = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.permissionFailure.rawValue,
            userInfo: nil
        )
        XCTAssertTrue(
            CloudKitUserFacingError.message(for: permission).contains("пригласить")
        )

        let constraint = NSError(
            domain: NSCocoaErrorDomain,
            code: NSManagedObjectConstraintMergeError,
            userInfo: nil
        )
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: constraint),
            CloudKitUserFacingError.genericSyncFailure
        )
    }

    func testIsUserFacingCoreDataFailureIgnoresCloudKit() {
        let ck = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkFailure.rawValue,
            userInfo: nil
        )
        XCTAssertFalse(PersistenceController.isUserFacingCoreDataFailure(ck))

        let cocoa = NSError(
            domain: NSCocoaErrorDomain,
            code: NSPersistentStoreIncompatibleVersionHashError,
            userInfo: nil
        )
        XCTAssertTrue(PersistenceController.isUserFacingCoreDataFailure(cocoa))

        let migrationText = NSError(
            domain: "OneCartTest",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Core Data migration failed"]
        )
        XCTAssertTrue(PersistenceController.isUserFacingCoreDataFailure(migrationText))
    }

    // MARK: - Helpers

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

    private func seedCart(
        repository: FamilySpaceRepository,
        name: String = "Семья",
        draft: ProductDraft? = nil
    ) async throws -> (familyID: UUID, listID: UUID, productID: UUID) {
        let familyID = try await repository.createFamilySpace(name: name)
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let productID = try await repository.addProduct(
            to: listID,
            draft: draft ?? productDraft()
        )
        return (familyID, listID, productID)
    }

    private func productDraft(
        name: String = "Хлеб",
        quantity: Double = 1,
        price: Double = 38,
        note: String = ""
    ) -> ProductDraft {
        ProductDraft(
            name: name,
            quantity: quantity,
            unit: .piece,
            category: .other,
            estimatedPrice: price,
            note: note
        )
    }

    private func fetchProduct(
        id: UUID,
        repository: FamilySpaceRepository
    ) -> ProductEntity? {
        for space in (try? repository.fetchFamilySpaces()) ?? [] {
            if let product = space.sortedProducts.first(where: { $0.id == id }) {
                return product
            }
        }
        return nil
    }

    private func assignStore(
        persistence: PersistenceController,
        productID: UUID,
        storeID: UUID
    ) async throws {
        try await persistence.performBackgroundTask { context in
            let productRequest = ProductEntity.fetchRequest()
            productRequest.predicate = NSPredicate(
                format: "id == %@ AND deletedAt == nil",
                productID as NSUUID
            )
            productRequest.fetchLimit = 1
            let storeRequest = StoreEntity.fetchRequest()
            storeRequest.predicate = NSPredicate(
                format: "id == %@ AND deletedAt == nil",
                storeID as NSUUID
            )
            storeRequest.fetchLimit = 1
            guard let product = try context.fetch(productRequest).first,
                  let store = try context.fetch(storeRequest).first
            else {
                throw RepositoryError.productNotFound
            }
            product.store = store
            product.updatedAt = Date()
        }
    }

    private static func fetchFamilySpace(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> FamilySpace? {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND deletedAt == nil",
            id as NSUUID
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func fetchList(
        id: UUID,
        in context: NSManagedObjectContext
    ) throws -> ShoppingListEntity? {
        let request = ShoppingListEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "id == %@ AND deletedAt == nil",
            id as NSUUID
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

private final class DenyAllPermissionAuthorizer: PermissionAuthorizing {
    func canUpdate(_: NSManagedObjectID) -> Bool { false }
    func canDelete(_: NSManagedObjectID) -> Bool { false }
}
