import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class SharedCartJoinTests: XCTestCase {
    func testOfferPromptsWhenSharedExistsAlongsidePrivate() async throws {
        let (session, _, privateID, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная"
        )

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.pendingSharedCartJoin?.id, sharedID)
        XCTAssertEqual(session.pendingSharedCartJoin?.cartName, "Семейная")
        XCTAssertEqual(session.activeFamilySpace?.id, privateID)
    }

    func testConfirmReplacesPrivateWithSharedAndMergesProducts() async throws {
        let (session, _, privateID, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            privateProduct: "Мой хлеб",
            sharedProduct: "Test 1"
        )

        try await session.offerSharedCartJoinIfNeededForTesting()
        await session.confirmSharedCartJoin()

        XCTAssertNil(session.pendingSharedCartJoin)
        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertNil(try session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: privateID)
        ).first)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Мой хлеб", "Test 1"])
    }

    func testDeclineKeepsPrivateCartAndSuppressesReprompt() async throws {
        let (session, _, privateID, sharedID) = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная"
        )

        try await session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(session.pendingSharedCartJoin?.id, sharedID)
        session.declineSharedCartJoin()

        XCTAssertNil(session.pendingSharedCartJoin)
        XCTAssertEqual(session.activeFamilySpace?.id, privateID)

        try await session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertNil(session.pendingSharedCartJoin)
        XCTAssertEqual(session.activeFamilySpace?.id, privateID)
    }

    func testAlreadyOnSharedDoesNotPrompt() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Алекс")
        let sharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Семейная",
            productName: "Test 1"
        )
        defaults.set(sharedID.uuidString, forKey: activeFamilyKey(accountID: account.id))

        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertNil(session.pendingSharedCartJoin)
        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
    }

    private func makeJoinFixture(
        privateName: String,
        sharedName: String,
        privateProduct: String? = nil,
        sharedProduct: String? = nil
    ) async throws -> (AppSession, OneCartAccount, UUID, UUID) {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Алекс")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )

        let privateID = try await repository.createFamilySpace(
            name: privateName,
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        if let privateProduct {
            let listID = try XCTUnwrap(
                repository.fetchFamilySpace(id: privateID)?.activeLists.first?.id
            )
            _ = try await repository.addProduct(
                to: listID,
                draft: productDraft(name: privateProduct)
            )
        }

        let sharedID = try await seedSharedCart(
            persistence: persistence,
            name: sharedName,
            productName: sharedProduct
        )
        defaults.set(privateID.uuidString, forKey: activeFamilyKey(accountID: account.id))

        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        persistence.container.viewContext.processPendingChanges()
        return (session, account, privateID, sharedID)
    }

    private func seedSharedCart(
        persistence: PersistenceController,
        name: String,
        productName: String?
    ) async throws -> UUID {
        let sharedID = UUID()
        let listID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = name
            space.createdAt = Date()
            space.updatedAt = Date()
            space.isHouseholdDefault = NSNumber(value: true)

            let list = ShoppingListEntity(context: context)
            try persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = listID
            list.title = String(localized: "common.default_list")
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = Date()
            list.updatedAt = Date()
            list.familySpace = space

            if let productName {
                let product = ProductEntity(context: context)
                try persistence.assign(product, toSameStoreAs: space, in: context)
                product.id = UUID()
                product.name = productName
                product.quantity = NSNumber(value: 1)
                product.unit = ProductUnit.piece.rawValue
                product.category = ProductCategory.other.rawValue
                product.estimatedPrice = NSNumber(value: 0)
                product.isPurchased = NSNumber(value: false)
                product.createdAt = Date()
                product.updatedAt = Date()
                product.familySpace = space
                product.list = list
            }
        }
        persistence.container.viewContext.processPendingChanges()
        return sharedID
    }

    private func activeFamilyKey(accountID: UUID) -> String {
        "onecart.active-family-space-id.\(accountID.uuidString)"
    }

    private func familySpaceRequest(id: UUID) -> NSFetchRequest<FamilySpace> {
        let request = FamilySpace.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        request.fetchLimit = 1
        return request
    }
}

final class ShareLinkJoinACLTests: XCTestCase {
    func testApplyReadWriteACLUpgradesNonePermission() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        XCTAssertNotEqual(share.publicPermission, .readWrite)
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertEqual(share.publicPermission, .readWrite)
    }

    func testApplyReadWriteACLIsIdempotent() {
        let share = CKShare(rootRecord: CKRecord(recordType: "FamilySpace"))
        XCTAssertTrue(OneCartShareLinkJoin.applyReadWriteACL(to: share))
        XCTAssertFalse(OneCartShareLinkJoin.applyReadWriteACL(to: share))
    }
}
