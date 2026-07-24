import CoreData
import CoreLocation
import XCTest
@testable import App

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

        guard case .migrated(let familyID) = first else {
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
        XCTAssertEqual(credential.displayName, "Иван Петров")
        XCTAssertEqual(
            credential.accountID,
            OneCartStableID.uuid(for: "apple:001234.abcd")
        )
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

    func testDeletableStarterFamilyDetection() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: AppModel.defaultFamilyName)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertTrue(
            FamilyCartMerge.isDeletableStarter(
                space,
                scope: persistence.scope(for: space)
            )
        )

        _ = try await repository.addProduct(
            to: try XCTUnwrap(space.activeLists.first?.id),
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
        XCTAssertFalse(
            FamilyCartMerge.isDeletableStarter(
                updated,
                scope: persistence.scope(for: updated)
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
        XCTAssertNil(repository.fetchFamilySpace(id: sourceID))
    }

    func testDefaultFamilyNameIsStable() {
        XCTAssertEqual(AppModel.defaultFamilyName, "Наша семья")
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
            to: try XCTUnwrap(list.id),
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

    func testManagedObjectModelHasOfflineSyncRelationshipsAndTimestamps() {
        let model = OneCartManagedObjectModel.makeModel()
        XCTAssertEqual(model.entities.count, 6)

        for entity in model.entities {
            XCTAssertTrue(entity.uniquenessConstraints.isEmpty)
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
        for name in ["FamilySpace", "Store", "ShoppingList", "Product", "PurchaseHistory", "HistoryItem"] {
            XCTAssertNotNil(model.entitiesByName[name]?.attributesByName["deletedAt"])
        }
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

    func testPopularStoreCatalogContainsRequestedNetworks() {
        let names = Set(StoreBrand.popular.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["АТБ", "Сільпо", "Auchan"]))
    }

    func testEveryPopularStoreHasOfficialCatalogRoute() {
        for brand in StoreBrand.popular {
            XCTAssertFalse(brand.catalogRoutes.isEmpty, "Missing catalog for \(brand.name)")
            XCTAssertTrue(
                brand.catalogRoutes.allSatisfy { brand.acceptsCatalogURL($0.url) },
                "Catalog host is not accepted for \(brand.name)"
            )
        }
    }

    func testNearbyStoreSearchResultsAreDeduplicated() {
        let first = StoreBranch(
            name: "АТБ",
            address: "Київ · Драгоманова, 2",
            coordinate: CLLocationCoordinate2D(latitude: 50.4110, longitude: 30.6410),
            distance: 500
        )
        let duplicate = StoreBranch(
            name: "ATB Market",
            address: "Київ · Драгоманова, 2",
            coordinate: CLLocationCoordinate2D(latitude: 50.4111, longitude: 30.6411),
            distance: 510
        )

        XCTAssertEqual(StoreBranch.deduplicated([first, duplicate]).count, 1)
        XCTAssertEqual(first.id, first.id)
    }

    func testCatalogProductMetadataIsPersisted() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Family")
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        let listID = try XCTUnwrap(space.activeLists.first?.id)
        let fetchedAt = Date(timeIntervalSince1970: 1_721_280_000)
        let promotionEndsAt = Date(timeIntervalSince1970: 1_721_366_399)

        _ = try await repository.addProduct(
            to: listID,
            draft: ProductDraft(
                name: "Засіб для миття посуду",
                quantity: 1,
                unit: .piece,
                category: .household,
                estimatedPrice: 79.99,
                note: "",
                imageURL: "https://example.com/product.jpg",
                sourceURL: "https://example.com/product/1",
                originalPrice: 119.99,
                loyaltyPrice: 74.99,
                catalogFetchedAt: fetchedAt,
                promotionEndsAt: promotionEndsAt
            )
        )

        let products = try persistence.container.viewContext.fetch(ProductEntity.fetchRequest())
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.imageURLValue?.absoluteString, "https://example.com/product.jpg")
        XCTAssertEqual(product.sourceURLValue?.absoluteString, "https://example.com/product/1")
        XCTAssertEqual(product.originalPrice?.doubleValue ?? 0, 119.99, accuracy: 0.001)
        XCTAssertEqual(product.loyaltyPrice?.doubleValue ?? 0, 74.99, accuracy: 0.001)
        XCTAssertEqual(product.catalogFetchedAt, fetchedAt)
        XCTAssertEqual(product.promotionEndsAt, promotionEndsAt)
    }

    func testCatalogProductCategoryIsInferredWithoutManualForm() {
        XCTAssertEqual(ProductCategory.inferred(from: "Засіб для миття посуду"), .household)
        XCTAssertEqual(ProductCategory.inferred(from: "Побутова хімія універсальний очисник"), .household)
        XCTAssertEqual(ProductCategory.inferred(from: "Молоко ультрапастеризоване"), .dairy)
        XCTAssertEqual(ProductCategory.inferred(from: "Банани вагові"), .produce)
        XCTAssertEqual(
            ProductCategory.inferred(from: "Фарш курячий Наша Ряба Соковитий охолоджений 500г"),
            .meat
        )
        XCTAssertEqual(
            ProductCategory.inferred(from: "Консерви 185г De Luxe Foods & Goods Selected"),
            .other
        )
        XCTAssertEqual(ProductCategory.inferred(from: "Кава Ambassador мелена 225г"), .drinks)
        XCTAssertEqual(ProductCategory.inferred(from: "Морква мита за 1 кг"), .produce)
        // Fruit-flavoured bakery must not leak into produce (Silpo filter bug).
        XCTAssertEqual(ProductCategory.inferred(from: "Торт фруктовий Київський 1кг"), .other)
        XCTAssertEqual(ProductCategory.inferred(from: "Пиріг з яблуками домашній"), .other)
        XCTAssertEqual(ProductCategory.inferred(from: "Печиво з фруктовою начинкою"), .other)
    }

    func testSilpoAndVarusCategoryShelvesOpenOfficialPages() throws {
        let silpo = try XCTUnwrap(StoreBrand.popular.first { $0.id == "silpo" })
        XCTAssertEqual(
            silpo.catalogURL(for: .produce)?.path,
            "/category/frukty-ovochi-4788"
        )
        XCTAssertTrue(
            silpo.catalogURLs(for: .dairy).contains {
                $0.path.contains("molochni-produkty-ta-iaitsia-234")
            }
        )
        XCTAssertEqual(
            silpo.productCategory(
                forCatalogURL: URL(string: "https://silpo.ua/category/frukty-ovochi-4788")
            ),
            .produce
        )
        XCTAssertEqual(
            silpo.productCategory(
                forCatalogURL: URL(string: "https://silpo.ua/category/pobutova-khimiia-4588")
            ),
            .household
        )

        let varus = try XCTUnwrap(StoreBrand.popular.first { $0.id == "varus" })
        XCTAssertEqual(varus.catalogURL(for: .produce)?.path, "/ovochi-svizhi")
        XCTAssertEqual(
            varus.productCategory(forCatalogURL: URL(string: "https://varus.ua/molochni-produkti")),
            .dairy
        )

        let fora = try XCTUnwrap(StoreBrand.popular.first { $0.id == "fora" })
        XCTAssertTrue(
            fora.catalogURLs(for: .produce).contains {
                $0.path.contains("frukty-ovochi-ta-solinnia-2790")
            }
        )
    }

    func testPageCategoryBeatsNameInferenceForCatalogFilters() throws {
        let cakeURL = try XCTUnwrap(URL(string: "https://silpo.ua/product/tort-fruktovyi-1"))
        let cakeOnProduceShelf = OfficialCatalogProduct(
            name: "Торт фруктовий",
            price: 299,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: cakeURL,
            storeName: "Сільпо",
            pageCategory: .produce
        )
        // If the store shelf itself is produce, we trust the aisle.
        XCTAssertEqual(cakeOnProduceShelf.category, .produce)

        let cakeFromMixedCatalog = OfficialCatalogProduct(
            name: "Торт фруктовий",
            price: 299,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: cakeURL,
            storeName: "Сільпо",
            pageCategory: nil
        )
        // Without aisle context, name inference must not call bakery "produce".
        XCTAssertEqual(cakeFromMixedCatalog.category, .other)
    }

    func testCatalogProductQualityRejectsFilesBadPricesAndFoodOnHousehold() throws {
        XCTAssertFalse(
            OfficialCatalogProductQuality.isAcceptableName("catalog.pdf")
        )
        XCTAssertFalse(
            OfficialCatalogProductQuality.isAcceptableName("Завантажити")
        )
        XCTAssertTrue(
            OfficialCatalogProductQuality.isAcceptableName("Засіб для миття посуду 500 мл")
        )

        XCTAssertFalse(
            OfficialCatalogProductQuality.isAcceptableName("Оберіть спосіб доставки")
        )
        XCTAssertFalse(
            OfficialCatalogProductQuality.isAcceptableName("Оберіть магазин")
        )

        // Title cleaning tests
        XCTAssertEqual(
            OfficialCatalogProductQuality.cleanTitle("Перець солодкий червоний купити в Києві та Україні за ціною від 99.95 грн ★ АТБ Маркет"),
            "Перець солодкий червоний"
        )
        XCTAssertEqual(
            OfficialCatalogProductQuality.cleanTitle("Кава мелена Jacobs 250г - купити за ціною 199 грн | Сільпо"),
            "Кава мелена Jacobs 250г"
        )
        XCTAssertEqual(
            OfficialCatalogProductQuality.cleanTitle("Молоко Яготинське 2.6% 900g ★ АТБ-Маркет"),
            "Молоко Яготинське 2.6% 900g"
        )

        // Summary cleaning tests
        XCTAssertNil(
            OfficialCatalogProductQuality.cleanSummary(
                "Кукурудза 1 шт, 1 гат. купити в супермаркеті ➡️ АТБМаркеті ✈️ Доставка додому та по всій Україні ✅ Великий вибір продуктів за низькими цінами ✨ Контроль якості та свіжості продуктів! ☎️ 0-800-500-415",
                productName: "Кукурудза 1 шт, 1 гат."
            )
        )

        let fileURL = try XCTUnwrap(
            URL(string: "https://shop.example.com/products/manual.pdf")
        )
        let productURL = try XCTUnwrap(
            URL(string: "https://shop.example.com/products/cleaner-500")
        )
        let silpoURL = try XCTUnwrap(
            URL(string: "https://silpo.ua/product/zasib-dlia-myttia-posudu-123")
        )
        let zakazURL = try XCTUnwrap(
            URL(string: "https://auchan.zakaz.ua/uk/products/zasib-domestos-1000ml--08717163094921/")
        )
        let varusURL = try XCTUnwrap(
            URL(string: "https://varus.ua/sredstvo-dlya-mytya-posudy-varto-clean-limon-500-ml")
        )
        let varusHome = try XCTUnwrap(URL(string: "https://varus.ua/own-clean"))
        XCTAssertFalse(OfficialCatalogProductQuality.isAcceptableProductURL(fileURL))
        XCTAssertTrue(OfficialCatalogProductQuality.isAcceptableProductURL(productURL))
        XCTAssertTrue(OfficialCatalogProductQuality.isAcceptableProductURL(silpoURL))
        XCTAssertTrue(OfficialCatalogProductQuality.isAcceptableProductURL(zakazURL))
        XCTAssertTrue(OfficialCatalogProductQuality.isAcceptableProductURL(varusURL))
        XCTAssertFalse(OfficialCatalogProductQuality.isAcceptableProductURL(varusHome))

        XCTAssertNil(
            OfficialCatalogProductQuality.sanitizedPrices(
                price: 0.2,
                originalPrice: nil,
                loyaltyPrice: nil
            )
        )
        XCTAssertNil(
            OfficialCatalogProductQuality.sanitizedPrices(
                price: 10,
                originalPrice: 120,
                loyaltyPrice: nil
            )?.originalPrice
        )
        let deepPromo = try XCTUnwrap(
            OfficialCatalogProductQuality.sanitizedPrices(
                price: 899,
                originalPrice: 2_482.92,
                loyaltyPrice: nil
            )
        )
        XCTAssertEqual(deepPromo.originalPrice ?? 0, 2_482.92, accuracy: 0.01)

        let sane = try XCTUnwrap(
            OfficialCatalogProductQuality.sanitizedPrices(
                price: 79.99,
                originalPrice: 119.99,
                loyaltyPrice: 74.5
            )
        )
        XCTAssertEqual(sane.price, 79.99, accuracy: 0.001)
        XCTAssertEqual(sane.originalPrice ?? 0, 119.99, accuracy: 0.001)
        XCTAssertEqual(sane.loyaltyPrice ?? 0, 74.5, accuracy: 0.001)

        let foodOnHousehold = OfficialCatalogProduct(
            name: "Банани вагові",
            price: 45,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: productURL,
            storeName: "АТБ"
        )
        let cleaner = OfficialCatalogProduct(
            name: "Засіб для миття посуду",
            price: 79.99,
            originalPrice: 119.99,
            imageURL: nil,
            sourceURL: productURL,
            storeName: "АТБ"
        )
        XCTAssertFalse(OfficialCatalogProductQuality.isPlausibleForHouseholdRoute(foodOnHousehold))
        XCTAssertTrue(OfficialCatalogProductQuality.isPlausibleForHouseholdRoute(cleaner))
        XCTAssertEqual(cleaner.discountPercent, 33)

        let upgraded = OfficialCatalogProductQuality.upgradedImageURL(
            try XCTUnwrap(
                URL(string: "https://img3.zakaz.ua/abc/1778389712-s200x200.jpg")
            )
        )
        XCTAssertEqual(
            upgraded?.absoluteString,
            "https://img3.zakaz.ua/abc/1778389712-s1350x1350.jpg"
        )
        let varusImage = OfficialCatalogProductQuality.upgradedImageURL(
            try XCTUnwrap(
                URL(string: "https://varus.ua:443/img/product/150/150/2549214")
            )
        )
        XCTAssertEqual(
            varusImage?.absoluteString,
            "https://varus.ua/img/product/420/420/2549214"
        )
    }

    func testCatalogMergeDropsInvalidScrapedRows() throws {
        let validURL = try XCTUnwrap(URL(string: "https://shop.example.com/products/valid-1"))
        let junkURL = try XCTUnwrap(URL(string: "https://shop.example.com/products/file.pdf"))
        let valid = OfficialCatalogProduct(
            name: "Гель для прання",
            price: 199,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: validURL,
            storeName: "Магазин"
        )
        let junkFile = OfficialCatalogProduct(
            name: "Інструкція",
            price: 12,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: junkURL,
            storeName: "Магазин"
        )
        let absurdPrice = OfficialCatalogProduct(
            name: "Ще один товар",
            price: 0.01,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/products/bad-price")),
            storeName: "Магазин"
        )

        let merged = OfficialCatalogProductCollection.merged(
            current: [],
            incoming: [valid, junkFile, absurdPrice]
        )
        XCTAssertEqual(merged.map(\.id), [valid.id])
    }

    func testDiscountRoutesPointToProductCollections() {
        let expectedPaths = [
            "atb": "/catalog/economy",
            "auchan": "/uk/custom-categories/promotions",
            "novus": "/uk/custom-categories/promotions",
            "metro": "/uk/custom-categories/promotions",
        ]

        for (brandID, path) in expectedPaths {
            let brand = StoreBrand.popular.first { $0.id == brandID }
            let discountRoute = brand?.catalogRoutes.first { $0.isDiscountRoute }
            XCTAssertEqual(discountRoute?.url.path, path)
            XCTAssertEqual(discountRoute?.containsOnlyDiscountedProducts, true)
        }
    }

    func testOfficialCategoryFiltersOpenCompleteStoreSections() {
        let expectedHouseholdPaths = [
            "auchan": "/uk/categories/household-chemicals-auchan",
            "novus": "/uk/categories/household-chemicals",
            "metro": "/uk/categories/chemicals-metro",
        ]

        for (brandID, path) in expectedHouseholdPaths {
            let brand = StoreBrand.popular.first { $0.id == brandID }
            XCTAssertEqual(brand?.catalogURL(for: .household)?.path, path)
            XCTAssertEqual(
                brand?.catalogRoutes.first { $0.title == "Для дома" }?.url.path,
                path
            )
            XCTAssertNotNil(brand?.catalogURL(for: .produce))
            XCTAssertNotNil(brand?.catalogURL(for: .dairy))
            XCTAssertNotNil(brand?.catalogURL(for: .meat))
            XCTAssertNotNil(brand?.catalogURL(for: .drinks))
            XCTAssertGreaterThan(brand?.catalogURLs(for: .household).count ?? 0, 1)
            XCTAssertGreaterThan(brand?.completeCatalogURLs.count ?? 0, 10)
            XCTAssertTrue(
                brand?.completeCatalogURLs.allSatisfy { $0.path.contains("/categories/") } == true
            )
        }
    }

    func testATBCatalogUsesOfficialCategoryPagesInsteadOfHomepage() throws {
        let brand = try XCTUnwrap(StoreBrand.popular.first { $0.id == "atb" })

        XCTAssertEqual(
            brand.catalogURL(for: .produce)?.path,
            "/catalog/287-ovochi-ta-frukti"
        )
        XCTAssertTrue(
            brand.catalogURLs(for: .household).contains {
                $0.path == "/catalog/308-pobutova-khimiya-ta-neprodovol-chi-tovari"
            }
        )
        XCTAssertEqual(brand.completeCatalogURLs.count, 23)
        XCTAssertTrue(
            brand.completeCatalogURLs.allSatisfy { $0.path.hasPrefix("/catalog/") }
        )
    }

    func testATBPriceParserDoesNotUseFractionDigitsAsPrices() throws {
        let regular = try XCTUnwrap(
            OfficialCatalogPriceParser.atbPriceInfo(
                from: "Сир плавлений 70 г Своя лінія 38% 23.90 грн/шт з карткою АТБ 22.68"
            )
        )
        XCTAssertEqual(regular.price, 23.90, accuracy: 0.001)
        XCTAssertNil(regular.originalPrice)
        XCTAssertEqual(regular.loyaltyPrice ?? 0, 22.68, accuracy: 0.001)

        let discounted = try XCTUnwrap(
            OfficialCatalogPriceParser.atbPriceInfo(
                from: "-34% Сир плавлений 70 г 14,90 грн/шт 22,90"
            )
        )
        XCTAssertEqual(discounted.price, 14.90, accuracy: 0.001)
        XCTAssertEqual(discounted.originalPrice ?? 0, 22.90, accuracy: 0.001)
        XCTAssertNil(discounted.loyaltyPrice)
    }

    func testDiscountCollectionExcludesProductsWithoutConfirmedOldPrice() throws {
        let regular = OfficialCatalogProduct(
            name: "Обычный товар",
            price: 40,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/products/regular")),
            storeName: "Магазин"
        )
        let discounted = OfficialCatalogProduct(
            name: "Акционный товар",
            price: 75,
            originalPrice: 100,
            imageURL: nil,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/products/discounted")),
            storeName: "Магазин"
        )

        XCTAssertEqual(
            OfficialCatalogProductCollection.discounted([regular, discounted]),
            [discounted]
        )
    }

    func testOfficialCatalogMergeUpdatesPriceWithoutDuplicatingProduct() throws {
        let imageURL = try XCTUnwrap(URL(string: "https://images.example.com/product.jpg"))
        let previous = OfficialCatalogProduct(
            name: "Засіб для миття посуду",
            price: 99.99,
            originalPrice: nil,
            imageURL: imageURL,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/product/1?ref=old")),
            storeName: "Магазин",
            details: OfficialCatalogProductDetails(
                summary: "Описание",
                ingredients: "Состав",
                producer: nil,
                country: "Украина"
            )
        )
        let refreshed = OfficialCatalogProduct(
            name: "Засіб для миття посуду",
            price: 79.99,
            originalPrice: 109.99,
            imageURL: nil,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/product/1?ref=new")),
            storeName: "Магазин",
            details: OfficialCatalogProductDetails(
                summary: nil,
                ingredients: nil,
                producer: "Производитель",
                country: nil
            )
        )

        let products = OfficialCatalogProductCollection.merged(
            current: [previous],
            incoming: [refreshed]
        )

        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.price ?? 0, 79.99, accuracy: 0.001)
        XCTAssertEqual(products.first?.originalPrice ?? 0, 109.99, accuracy: 0.001)
        XCTAssertEqual(products.first?.imageURL, imageURL)
        XCTAssertEqual(products.first?.details?.summary, "Описание")
        XCTAssertEqual(products.first?.details?.ingredients, "Состав")
        XCTAssertEqual(products.first?.details?.producer, "Производитель")
        XCTAssertEqual(products.first?.details?.country, "Украина")
    }

    func testOfficialPromotionExpiryComesFromRetailerDate() throws {
        let formatter = ISO8601DateFormatter()
        let fetchedAt = try XCTUnwrap(formatter.date(from: "2026-07-18T08:00:00Z"))
        let structuredExpiry = try XCTUnwrap(
            OfficialCatalogPromotionParser.expiryDate(
                from: "2026-07-19",
                fetchedAt: fetchedAt
            )
        )
        let visibleExpiry = try XCTUnwrap(
            OfficialCatalogPromotionParser.expiryDate(
                from: "Акція до 19.07",
                fetchedAt: fetchedAt
            )
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Kyiv"))
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: structuredExpiry
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
        XCTAssertEqual(components.second, 59)
        XCTAssertEqual(visibleExpiry, structuredExpiry)
        XCTAssertNil(
            OfficialCatalogPromotionParser.expiryDate(
                from: "Знижка цього тижня",
                fetchedAt: fetchedAt
            )
        )
    }

    func testExpiredPromotionIsNotPresentedAsDiscount() throws {
        let now = Date(timeIntervalSince1970: 1_721_280_000)
        let product = OfficialCatalogProduct(
            name: "Акційний товар",
            price: 50,
            originalPrice: 100,
            imageURL: nil,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/product/expired")),
            storeName: "Магазин",
            promotionEndsAt: now.addingTimeInterval(-1),
            fetchedAt: now.addingTimeInterval(-60),
            isDetailVerified: true
        )

        XCTAssertNil(product.discountPercent(at: now))
        XCTAssertFalse(product.isPriceFresh(at: now))
        XCTAssertNil(product.draft.originalPrice)
    }

    func testFreshRegularPriceClearsPreviousPromotion() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://shop.example.com/product/1"))
        let firstFetch = Date(timeIntervalSince1970: 1_721_280_000)
        let previous = OfficialCatalogProduct(
            name: "Товар",
            price: 70,
            originalPrice: 100,
            imageURL: nil,
            sourceURL: sourceURL,
            storeName: "Магазин",
            promotionEndsAt: firstFetch.addingTimeInterval(3_600),
            fetchedAt: firstFetch,
            isDetailVerified: true
        )
        let refreshed = OfficialCatalogProduct(
            name: "Товар",
            price: 90,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: sourceURL,
            storeName: "Магазин",
            promotionEndsAt: nil,
            fetchedAt: firstFetch.addingTimeInterval(600),
            isDetailVerified: true
        )

        let merged = try XCTUnwrap(
            OfficialCatalogProductCollection.merged(
                current: [previous],
                incoming: [refreshed]
            ).first
        )
        XCTAssertEqual(merged.price, 90, accuracy: 0.001)
        XCTAssertNil(merged.originalPrice)
        XCTAssertNil(merged.promotionEndsAt)
    }

    func testOfficialPriceBasisParserUsesRetailerUnit() {
        let kilogram = OfficialCatalogPriceBasisParser.parse(
            rawUnit: "kg",
            priceText: "75,00 грн",
            productName: "Банани"
        )
        XCTAssertEqual(kilogram.quantity, 1, accuracy: 0.001)
        XCTAssertEqual(kilogram.unit, .kg)

        let hundredGrams = OfficialCatalogPriceBasisParser.parse(
            rawUnit: nil,
            priceText: "Ціна за 100 г — 32,90 грн",
            productName: "Сир"
        )
        XCTAssertEqual(hundredGrams.quantity, 100, accuracy: 0.001)
        XCTAssertEqual(hundredGrams.unit, .g)
    }

    func testOfficialCatalogPriceAndDiscountSorting() throws {
        XCTAssertEqual(
            OfficialCatalogPriceParser.value(from: "1 299,50 грн") ?? 0,
            1_299.50,
            accuracy: 0.001
        )

        let regular = OfficialCatalogProduct(
            name: "Товар без акции",
            price: 40,
            originalPrice: nil,
            imageURL: nil,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/product/regular")),
            storeName: "Магазин"
        )
        let discounted = OfficialCatalogProduct(
            name: "Товар со скидкой",
            price: 75,
            originalPrice: 150,
            imageURL: nil,
            sourceURL: try XCTUnwrap(URL(string: "https://shop.example.com/product/discount")),
            storeName: "Магазин"
        )

        XCTAssertEqual(
            OfficialCatalogSort.priceAscending.apply(to: [discounted, regular]).first?.id,
            regular.id
        )
        XCTAssertEqual(
            OfficialCatalogSort.discount.apply(to: [regular, discounted]).first?.id,
            discounted.id
        )
        XCTAssertEqual(discounted.discountPercent, 50)
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
        let invite = FamilyInviteLink(
            id: try XCTUnwrap(UUID(uuidString: "7A4E7A84-38A1-4E6B-8E4C-6A5D0D18B0C2")),
            familyName: "Наша группа",
            url: shareURL
        )

        XCTAssertTrue(invite.shareMessage.contains(shareURL.absoluteString))
        XCTAssertTrue(invite.shareMessage.contains("Наша группа"))
        XCTAssertTrue(invite.shareMessage.contains("группе"))
        XCTAssertTrue(invite.shareMessage.hasPrefix("OneCart"))
        XCTAssertEqual(invite.shareTitle, "OneCart")
        XCTAssertEqual(invite.expiresAt, .distantFuture)
        XCTAssertFalse(OneCartShareBranding.thumbnailImageData.isEmpty)
    }

    private func makeInMemoryRepository() async throws
        -> (PersistenceController, FamilySpaceRepository) {
        let persistence = PersistenceController(inMemory: true)
        try await persistence.load()
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        return (persistence, repository)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "OneCartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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

private final class DenyAllPermissionAuthorizer: PermissionAuthorizing {
    func canUpdate(_ objectID: NSManagedObjectID) -> Bool { false }
    func canDelete(_ objectID: NSManagedObjectID) -> Bool { false }
}
