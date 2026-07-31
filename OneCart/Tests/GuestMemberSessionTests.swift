import CoreData
@testable import OneCart
import XCTest

@MainActor
final class GuestMemberSessionTests: XCTestCase {
    func testGuestSessionActivatesSharedCartAsMember() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")

        XCTAssertEqual(fixture.session.activeFamilySpace?.id, fixture.sharedID)
        XCTAssertEqual(fixture.session.access, .member)
        XCTAssertTrue(fixture.session.access?.isParticipant == true)
        XCTAssertFalse(fixture.session.access?.isOwner == true)
        XCTAssertEqual(fixture.session.cartTitle, "Семейная")
        XCTAssertEqual(fixture.session.familySpaces.map(\.id), [fixture.sharedID])
        XCTAssertEqual(Set(fixture.session.products.map(\.displayName)), ["Milk"])
        XCTAssertNotNil(try fixture.session.persistence.container.viewContext.fetch(
            familySpaceRequest(id: fixture.privateID)
        ).first)
    }

    func testGuestCannotRenameOrRevokeSharedCart() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")
        let sharedID = fixture.sharedID

        await fixture.session.renameActiveCart("Хак")
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(fixture.session.cartTitle, "Семейная")
        XCTAssertEqual(fixture.session.account?.displayName, "Tim")

        await fixture.session.revokeInviteLink()
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sharedID)
        XCTAssertNil(fixture.session.userAlert)
    }

    func testGuestMetadataFallbackUsesMemberAccess() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()

        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Семейная"
            space.createdAt = Date()
            space.updatedAt = Date()
        }
        persistence.container.viewContext.processPendingChanges()

        let space = try XCTUnwrap(
            persistence.container.viewContext.fetch(familySpaceRequest(id: sharedID)).first
        )
        let backend = CloudKitBackendService(persistence: persistence)
        let account = OneCartAccount(id: UUID(), displayName: "Tim")
        XCTAssertEqual(backend.access(for: space), .member)

        let members = try backend.familyMembers(for: space, account: account)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members[0].access, .member)
        XCTAssertTrue(members[0].isCurrentUser)
    }

    func testGuestReturnsToPersonalWhenSharedGone() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")
        XCTAssertEqual(fixture.session.access, .member)

        try await fixture.session.repository.archiveFamilySpace(id: fixture.sharedID)
        try await fixture.session.reactivatePersonalCartIfNeededForTesting()

        XCTAssertEqual(fixture.session.activeFamilySpace?.id, fixture.privateID)
        XCTAssertEqual(fixture.session.access, .owner)
        XCTAssertTrue(fixture.session.familySpaces.allSatisfy {
            fixture.session.persistence.scope(for: $0) == .private
        })
    }

    private struct GuestFixture {
        var session: AppSession
        var privateID: UUID
        var sharedID: UUID
    }

    private func makeGuestFixture(
        sharedName: String,
        sharedProduct: String
    ) async throws -> GuestFixture {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Tim")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )

        let privateID = try await repository.createFamilySpace(
            name: AppSession.householdCartName(for: account),
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        let privateListID = try XCTUnwrap(
            repository.fetchFamilySpace(id: privateID)?.activeLists.first?.id
        )
        _ = try await repository.addProduct(
            to: privateListID,
            draft: productDraft(name: "Private bread")
        )

        let sharedID = UUID()
        let listID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = sharedName
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

            let product = ProductEntity(context: context)
            try persistence.assign(product, toSameStoreAs: space, in: context)
            product.id = UUID()
            product.name = sharedProduct
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
        persistence.container.viewContext.processPendingChanges()
        defaults.set(privateID.uuidString, forKey: activeFamilyKey(accountID: account.id))

        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()

        return GuestFixture(session: session, privateID: privateID, sharedID: sharedID)
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

extension AppSession {
    func reactivatePersonalCartIfNeededForTesting() async throws {
        guard let account else { return }
        try await household.reactivatePersonalCartIfNeeded(for: account)
    }
}
