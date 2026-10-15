import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class PersistenceRoutingTests: XCTestCase {
    func testPrivateAndSharedStoreRouting() async throws {
        let persistence = makeInMemoryPersistence()
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

        let viewContext = persistence.container.viewContext
        await viewContext.perform {
            viewContext.processPendingChanges()
        }

        let privateSpace = try XCTUnwrap(repository.fetchFamilySpace(id: privateID))
        let sharedSpace = try XCTUnwrap(repository.fetchFamilySpace(id: sharedID))
        XCTAssertFalse(privateSpace.objectID.isTemporaryID)
        XCTAssertFalse(sharedSpace.objectID.isTemporaryID)
        XCTAssertNotNil(privateSpace.objectID.persistentStore)
        XCTAssertNotNil(sharedSpace.objectID.persistentStore)

        let privateScope = try XCTUnwrap(persistence.scope(for: privateSpace))
        let sharedScope = try XCTUnwrap(persistence.scope(for: sharedSpace))
        XCTAssertEqual(privateScope, .private)
        XCTAssertEqual(sharedScope, .shared)
    }

    func test_REQ_AUTH_050_storeURLsMapToPrivateAndSharedScopes() {
        let directory = FileManager.default.temporaryDirectory
        XCTAssertEqual(
            PersistenceController.scope(forStoreURL: directory.appendingPathComponent("OneCart-private.sqlite")),
            .private
        )
        XCTAssertEqual(
            PersistenceController.scope(forStoreURL: directory.appendingPathComponent("OneCart-shared.sqlite")),
            .shared
        )
        XCTAssertNil(PersistenceController.scope(forStoreURL: directory.appendingPathComponent("OneCart.sqlite")))
        XCTAssertNil(PersistenceController.scope(forStoreURL: nil))
    }

    func test_REQ_AUTH_080_storeFilePredicateKeepsDiagnosticsFolders() {
        let directory = FileManager.default.temporaryDirectory
        for name in ["OneCart-private.sqlite", "OneCart-shared.sqlite-wal", "onecart-private.sqlite-shm"] {
            XCTAssertTrue(PersistenceController.isOneCartStoreFile(directory.appendingPathComponent(name)), name)
        }
        for name in ["OneCart-diagnostics", "Other.sqlite", "OneCart.sqlite"] {
            XCTAssertFalse(PersistenceController.isOneCartStoreFile(directory.appendingPathComponent(name)), name)
        }
    }

    func test_REQ_AUTH_040_blankAndWhitespaceOnlyNamesNormalizeToNil() {
        XCTAssertNil("".nilIfBlank)
        XCTAssertNil(" \n\t ".nilIfBlank)
        XCTAssertEqual("  Alex ".nilIfBlank, "Alex")
    }

    func test_REQ_SHARE_050_discardingTheSharedCartLeavesPrivateCartsUntouched() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
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

        try await repository.discardLocalSharedFamilySpace(id: privateID)
        try await repository.discardLocalSharedFamilySpace(id: sharedID)

        let viewContext = persistence.container.viewContext
        XCTAssertNotNil(try viewContext.fetch(familySpaceRequest(id: privateID)).first)
        XCTAssertNil(try viewContext.fetch(familySpaceRequest(id: sharedID)).first)
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
        XCTAssertEqual(lists.first?.title, String(localized: "common.default_list"))
        // v1.2.1 shows only lists whose stored status is "active".
        XCTAssertEqual(lists.first?.status, "active")
        XCTAssertEqual(
            lists.first?.objectID.persistentStore,
            space.objectID.persistentStore
        )
    }

    func testOfflineRepositorySaveSurvivesContextReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let persistence = PersistenceController(
            inMemory: false,
            storeDirectoryURL: directory,
            cloudKitEnabled: false
        )

        let productCount: Int
        let productName: String?
        do {
            try await persistence.load()
            let repository = FamilySpaceRepository(
                persistence: persistence,
                permissionAuthorizer: AllowAllPermissionAuthorizer()
            )
            let familyID = try await repository.createFamilySpace(name: "Offline")
            let listID = try XCTUnwrap(
                repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
            )

            _ = try await repository.addProduct(
                to: listID,
                draft: ProductDraft(name: "Хлеб", category: .other)
            )

            persistence.container.viewContext.reset()

            let productRequest = ProductEntity.fetchRequest()
            productRequest.predicate = NSPredicate(
                format: "familySpace.id == %@",
                familyID as NSUUID
            )
            let products = try persistence.container.viewContext.fetch(productRequest)
            productCount = products.count
            productName = products.first?.displayName
            persistence.container.viewContext.reset()
        }

        XCTAssertEqual(productCount, 1)
        XCTAssertEqual(productName, "Хлеб")

        try? persistence.hardResetPersistentStores()
        try? FileManager.default.removeItem(at: directory)
    }
}
