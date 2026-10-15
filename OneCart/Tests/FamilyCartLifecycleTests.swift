import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class FamilyCartLifecycleTests: XCTestCase {
    func test_REQ_AUTH_050_claimUnassignedFamilySpacesStampsPrivateOnly() async throws {
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

    func test_REQ_CART_010_activeCartSurvivesCompleteAndArchive() async throws {
        let (persistence, repository) = try await makeInMemoryRepository()
        let (familyID, listID, breadID) = try await seedCart(repository: repository)
        let milkID = try await repository.addProduct(to: listID, draft: productDraft(name: "Молоко"))
        try await repository.togglePurchased(id: breadID, participantDisplayName: "Игорь")
        try await repository.togglePurchased(id: milkID, participantDisplayName: "Игорь")

        let historyID = try await repository.archivePurchasedBefore(
            listID: listID,
            cutoff: Date().addingTimeInterval(60)
        )
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        XCTAssertNotNil(historyID)
        let space = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertNil(space.deletedAt)
        XCTAssertEqual(try repository.fetchFamilySpaces().map(\.id), [familyID])
        XCTAssertTrue(space.sortedProducts.isEmpty)
        XCTAssertEqual(space.sortedHistory.map(\.id), [historyID])
        let list = try XCTUnwrap(space.activeLists.first)
        XCTAssertEqual(list.id, listID)
        XCTAssertNil(list.deletedAt)

        let juiceID = try await repository.addProduct(to: listID, draft: productDraft(name: "Сок"))
        try await repository.togglePurchased(id: juiceID, participantDisplayName: "Игорь")
        try await repository.completePurchased(listID: listID)
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let afterComplete = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertNil(afterComplete.deletedAt)
        XCTAssertEqual(afterComplete.activeLists.map(\.id), [listID])

        let nextID = try await repository.addProduct(to: listID, draft: productDraft(name: "Сыр"))
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        let reused = try XCTUnwrap(repository.fetchFamilySpace(id: familyID))
        XCTAssertEqual(reused.sortedProducts.map(\.id), [nextID])
    }

    func testRenameFamilySpaceUpdatesDisplayName() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let familyID = try await repository.createFamilySpace(name: "Старое")
        try await repository.renameFamilySpace(id: familyID, name: "  Новое имя  ")
        XCTAssertEqual(
            try repository.fetchFamilySpace(id: familyID)?.displayName,
            "Новое имя"
        )
    }
}
