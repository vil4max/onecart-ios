import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class PersistenceRoutingTests: XCTestCase {
    func testPrivateAndSharedStoreRouting() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
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
        XCTAssertEqual(lists.first?.displayTitle, String(localized: "common.default_list"))
        XCTAssertEqual(lists.first?.statusValue, .active)
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
