import CloudKit
import CoreData
@testable import OneCart
import XCTest

final class OneCartTests: XCTestCase {
    func testPrivateAndSharedStoreRouting() async throws {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )

        let privateID = try await repository.createFamilySpace(name: "Private")
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Shared"
            space.createdAt = Date()
            space.updatedAt = Date()
        }

        let privateSpace = try XCTUnwrap(repository.fetchFamilySpace(id: privateID))
        let sharedSpace = try XCTUnwrap(repository.fetchFamilySpace(id: sharedID))
        XCTAssertEqual(persistence.scope(for: privateSpace), .private)
        XCTAssertEqual(persistence.scope(for: sharedSpace), .shared)
    }

    func testCreatingFamilySpaceAlsoCreatesGeneralList() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let id = try await repository.createFamilySpace(name: "Наша группа")
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: id))

        let request = ShoppingListEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "familySpace.id == %@",
            id as NSUUID
        )
        let lists = try persistence.container.viewContext.fetch(request)

        XCTAssertEqual(space.displayName, "Наша группа")
        XCTAssertEqual(lists.count, 1)
        XCTAssertEqual(lists.first?.displayTitle, "Общий список")
        XCTAssertEqual(lists.first?.statusValue, .active)
        XCTAssertEqual(
            lists.first?.objectID.persistentStore,
            space.objectID.persistentStore
        )
    }

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

    func testStableIDPreventsDuplicateStores() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Family")
        let storeID = UUID()
        let draft = StoreDraft(
            name: "АТБ",
            icon: "АТБ",
            colorHex: "#315B9A",
            address: nil,
            externalAppURL: nil,
            isPinned: true
        )

        _ = try await repository.addStore(
            to: familyID,
            id: storeID,
            draft: draft
        )
        _ = try await repository.addStore(
            to: familyID,
            id: storeID,
            draft: draft
        )

        let request = StoreEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "familySpace.id == %@",
            familyID as NSUUID
        )
        XCTAssertEqual(
            try persistence.container.viewContext.fetch(request).count,
            1
        )
    }

    func testRepositoryEnforcesReadOnlyPermission() async throws {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let ownerRepository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await ownerRepository.createFamilySpace(name: "Family")
        let readOnlyRepository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: DenyAllPermissionAuthorizer()
        )

        do {
            _ = try await readOnlyRepository.addStore(
                to: familyID,
                draft: StoreDraft(
                    name: "Store",
                    icon: "S",
                    colorHex: "#34785B",
                    address: nil,
                    externalAppURL: nil,
                    isPinned: false
                )
            )
            XCTFail("Expected permission error")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }
    }

    func testFamilyCacheIsScopedToAuthenticatedUser() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let firstUser = UUID()
        let secondUser = UUID()
        _ = try await repository.createFamilySpace(
            name: "Первая группа",
            cachedForUserID: firstUser,
            serverRole: FamilyAccess.owner.rawValue,
            needsRemoteCreation: true
        )

        XCTAssertEqual(try repository.fetchFamilySpaces(for: firstUser).count, 1)
        XCTAssertTrue(try repository.fetchFamilySpaces(for: secondUser).isEmpty)
    }

    func testSharedCartVisibleAlongsideOwnPrivateCart() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let ownerID = UUID()
        let memberID = UUID()

        let privateID = try await repository.createFamilySpace(
            name: "Моя",
            cachedForUserID: memberID,
            isHouseholdDefault: true
        )
        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Семейная"
            space.createdAt = Date()
            space.updatedAt = Date()
            space.isHouseholdDefault = NSNumber(value: true)
        }

        let visibleToMember = try repository.fetchFamilySpaces(for: memberID)
        XCTAssertEqual(Set(visibleToMember.compactMap(\.id)), [privateID, sharedID])

        let visibleToOwner = try repository.fetchFamilySpaces(for: ownerID)
        XCTAssertEqual(visibleToOwner.compactMap(\.id), [sharedID])
        XCTAssertFalse(visibleToOwner.contains { $0.id == privateID })
    }

    func testFamilyAccessAllowsSharedListEditing() {
        XCTAssertTrue(FamilyAccess.owner.canEdit)
        XCTAssertTrue(FamilyAccess.member.canEdit)
        XCTAssertTrue(FamilyAccess.owner.isOwner)
        XCTAssertTrue(FamilyAccess.member.isParticipant)
    }

    func testStableIDIsDeterministic() {
        let first = OneCartStableID.uuid(for: "apple:user-1")
        let second = OneCartStableID.uuid(for: "apple:user-1")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            OneCartStableID.uuid(for: "apple:user-1"),
            OneCartStableID.uuid(for: "apple:user-2")
        )
    }

    func testAppleSignInCredentialBuildsDisplayNameAndAccountID() {
        let credential = AppleSignInCredential(
            userID: "001234.abcd",
            email: "user@example.com",
            givenName: "Иван",
            familyName: "Петров"
        )
        XCTAssertEqual(credential.providedDisplayName, "Иван Петров")
        XCTAssertEqual(credential.displayName, "Иван Петров")
        XCTAssertEqual(
            credential.accountID,
            OneCartStableID.uuid(for: "apple:001234.abcd")
        )

        let withoutName = AppleSignInCredential(
            userID: "001234.abcd",
            email: nil,
            givenName: nil,
            familyName: nil
        )
        XCTAssertNil(withoutName.providedDisplayName)
        XCTAssertEqual(withoutName.displayName, "Пользователь")
    }

    func testKeychainAppleSignInCredentialStorePersistsCredential() {
        let service = "onecart.tests.\(UUID().uuidString)"
        let store = KeychainAppleSignInCredentialStore(service: service)
        let credential = AppleSignInCredential(
            userID: "001234.abcd",
            email: nil,
            givenName: "Test",
            familyName: nil
        )
        store.save(credential)
        XCTAssertEqual(store.load(), credential)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testDeletedProductIsKeptAsSyncTombstoneAndHiddenFromUI() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Offline")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(family.activeLists.first?.id)
        let productID = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Хлеб",
                quantity: 1,
                unit: .piece,
                category: .other,
                estimatedPrice: 38,
                note: ""
            )
        )

        try await repository.deleteProduct(id: productID)

        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let stored = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)
        XCTAssertNotNil(stored.deletedAt)
        XCTAssertTrue(try XCTUnwrap(repository.fetchFamilySpace(id: familyID)).sortedProducts.isEmpty)
    }

    func testSameNamedProductsStayAsSeparateCartLines() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Семья")
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let draft = ProductDraft(
            name: "Молоко",
            quantity: 1,
            unit: .piece,
            category: .dairy,
            estimatedPrice: 40,
            note: "",
            sourceURL: "https://shop.example.com/milk"
        )

        let firstID = try await repository.addProduct(
            to: listID,
            draft: draft,
            purchasedByName: "Анна"
        )
        let secondID = try await repository.addProduct(
            to: listID,
            draft: draft,
            purchasedByName: "Игорь"
        )

        XCTAssertNotEqual(firstID, secondID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let milk = space.sortedProducts.filter { $0.displayName == "Молоко" }
        XCTAssertEqual(milk.count, 2, "Identical names must not be summed into one line")
        XCTAssertEqual(
            milk.map(\.quantityValue).reduce(0, +),
            2,
            "Each line keeps its own quantity"
        )
    }

    func testAddProductLandsInSameStoreAsFamilyForCloudKitSync() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(
            name: AppModel.defaultFamilyName,
            isHouseholdDefault: true
        )
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let list = try XCTUnwrap(family.activeLists.first)
        let listID = try XCTUnwrap(list.id)

        let productID = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Молоко",
                quantity: 2,
                unit: .piece,
                category: .dairy,
                estimatedPrice: 42,
                note: "2.5%"
            )
        )

        let request = ProductEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", productID as NSUUID)
        let product = try XCTUnwrap(persistence.container.viewContext.fetch(request).first)

        XCTAssertEqual(product.displayName, "Молоко")
        XCTAssertEqual(product.list?.id, listID)
        XCTAssertEqual(product.familySpace?.id, familyID)
        XCTAssertEqual(product.isPurchasedValue, false)
        XCTAssertEqual(
            product.objectID.persistentStore?.url,
            family.objectID.persistentStore?.url,
            "Product must share the FamilySpace store or CloudKit will not sync the share graph"
        )
        XCTAssertEqual(persistence.scope(for: product), .private)

        let reloaded = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(reloaded.sortedProducts.count, 1)
        XCTAssertEqual(reloaded.sortedProducts.first?.id, productID)
    }

    func testAddProductVisibleAfterViewContextMerge() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Sync")
        let family = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(family.activeLists.first?.id)

        _ = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Яйца",
                quantity: 10,
                unit: .piece,
                category: .dairy,
                estimatedPrice: 65,
                note: ""
            )
        )

        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        let products = try persistence.container.viewContext.fetch(ProductEntity.fetchRequest())
            .filter { $0.familySpace?.id == familyID && $0.deletedAt == nil }
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.displayName, "Яйца")
    }

    func testOfflineRepositorySaveSurvivesContextReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(name: "Offline")
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let list = try XCTUnwrap(space.activeLists.first)

        _ = try await repository.addProduct(
            to: XCTUnwrap(list.id),
            draft: ProductDraft(
                name: "Хлеб",
                quantity: 1,
                unit: .piece,
                category: .other,
                estimatedPrice: 38,
                note: ""
            )
        )

        persistence.container.viewContext.reset()

        let productRequest = ProductEntity.fetchRequest()
        productRequest.predicate = NSPredicate(
            format: "familySpace.id == %@",
            familyID as NSUUID
        )
        let products = try persistence.container.viewContext.fetch(productRequest)
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.displayName, "Хлеб")
    }

    func testStoreLocationIsPersistedWithSelectedBranch() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Family")

        let storeID = try await repository.addStore(
            to: familyID,
            draft: StoreDraft(
                name: "АТБ",
                icon: "АТБ",
                colorHex: "#E30613",
                address: "Київ · Хрещатик, 1",
                latitude: 50.4501,
                longitude: 30.5234,
                externalAppURL: "https://www.atbmarket.com",
                isPinned: false
            )
        )

        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let store = try XCTUnwrap(space.sortedStores.first { $0.id == storeID })
        XCTAssertEqual(store.address, "Київ · Хрещатик, 1")
        XCTAssertEqual(store.latitudeValue ?? 0, 50.4501, accuracy: 0.000_001)
        XCTAssertEqual(store.longitudeValue ?? 0, 30.5234, accuracy: 0.000_001)
    }

    func testOfficialProductMediaUsesSelectedStoreCatalogOnly() {
        XCTAssertEqual(
            OfficialProductMedia.resolve(
                productName: "Бананы",
                storeName: "АТБ"
            )?.sourceName,
            "АТБ"
        )
        XCTAssertNil(
            OfficialProductMedia.resolve(
                productName: "Молоко",
                storeName: "АТБ"
            )
        )
        XCTAssertEqual(
            OfficialProductMedia.resolve(
                productName: "Молоко",
                storeName: "Сільпо"
            )?.sourceName,
            "Сільпо"
        )
    }

    func testCloudKitFamilyInviteShareMessageContainsShareURL() throws {
        let shareURL = try XCTUnwrap(
            URL(string: "https://www.icloud.com/share/onecart-family")
        )
        let invite = try FamilyInviteLink(
            id: XCTUnwrap(UUID(uuidString: "7A4E7A84-38A1-4E6B-8E4C-6A5D0D18B0C2")),
            familyName: "Наша группа",
            url: shareURL
        )

        XCTAssertTrue(invite.shareMessage.contains(shareURL.absoluteString))
        XCTAssertTrue(invite.shareMessage.contains("Наша группа"))
        XCTAssertTrue(invite.shareMessage.contains("корзине"))
        XCTAssertTrue(invite.shareMessage.hasPrefix("OneCart"))
        XCTAssertEqual(invite.shareTitle, "OneCart")
        XCTAssertEqual(invite.expiresAt, .distantFuture)
        XCTAssertFalse(OneCartShareBranding.thumbnailImageData.isEmpty)
    }

    func testCloudKitUserFacingErrorReplacesOpaquePartialFailure() {
        let opaque = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: nil
        )
        let message = CloudKitUserFacingError.message(for: opaque)
        XCTAssertEqual(message, CloudKitUserFacingError.genericSyncFailure)
        XCTAssertFalse(message.lowercased().contains("ckerrordomain"))
    }

    func testCloudKitUserFacingErrorUnwrapsNestedQuotaExceeded() {
        let quota = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.quotaExceeded.rawValue,
            userInfo: nil
        )
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["record": quota]]
        )
        let message = CloudKitUserFacingError.message(for: partial)
        XCTAssertTrue(message.contains("iCloud"))
        XCTAssertTrue(message.contains("место"))
    }

    func testCloudKitUserFacingErrorDetectsNetworkFailure() {
        let network = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkUnavailable.rawValue,
            userInfo: nil
        )
        XCTAssertTrue(CloudKitUserFacingError.isNetworkError(network))
    }

    func testCloudKitUserFacingErrorMapsProductionSchemaFailure() {
        let nested = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.invalidArguments.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Cannot create new type CD_ShoppingList in production schema",
            ]
        )
        let mirroring = NSError(
            domain: NSCocoaErrorDomain,
            code: 134_400,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The operation couldn’t be completed. Request was aborted because the mirroring delegate never successfully initialized due to error: Partial Failure",
                NSUnderlyingErrorKey: nested,
            ]
        )
        let message = CloudKitUserFacingError.message(for: mirroring)
        XCTAssertEqual(message, CloudKitUserFacingError.productionSchemaMissing)
        XCTAssertTrue(CloudKitUserFacingError.isProductionSchemaFailure(mirroring))
        XCTAssertFalse(message.contains("CD_ShoppingList"))
        XCTAssertFalse(message.contains("mirroring delegate"))
    }

    func testCloudKitUserFacingErrorMapsProductionSchemaFromUserInfoCrumb() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Partial Failure",
                "CKErrorDescription":
                    "Cannot create new type CD_ShoppingList in production schema",
            ]
        )
        XCTAssertTrue(CloudKitUserFacingError.isProductionSchemaFailure(error))
        XCTAssertEqual(
            CloudKitUserFacingError.message(for: error),
            CloudKitUserFacingError.productionSchemaMissing
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
