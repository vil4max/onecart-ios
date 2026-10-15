import CloudKit
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class GuestMemberSessionTests: XCTestCase {
    func test_REQ_SHARE_090_guestSessionActivatesSharedCartAsMember() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")

        XCTAssertEqual(fixture.session.activeFamilySpace?.id, fixture.sharedID)
        XCTAssertEqual(fixture.session.access, .member)
        XCTAssertTrue(fixture.session.access?.isParticipant == true)
        XCTAssertFalse(fixture.session.access?.isOwner == true)
        XCTAssertEqual(fixture.session.cartTitle, "Семейная")
        XCTAssertEqual(fixture.session.familySpaces.map(\.id), [fixture.sharedID])
        XCTAssertEqual(Set(fixture.session.products.map(\.displayName)), ["Milk"])
        XCTAssertNotNil(
            try fixture.session.persistence.container.viewContext.fetch(
                familySpaceRequest(id: fixture.privateID)
            ).first)
    }

    func test_REQ_CART_110_guestCannotRenameOrRevokeSharedCart() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")
        let sharedID = fixture.sharedID

        await fixture.session.renameActiveCart("Хак")
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(fixture.session.cartTitle, "Семейная")
        XCTAssertEqual(fixture.session.account?.displayName, "Sam")

        await fixture.session.revokeInviteLink()
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sharedID)
        XCTAssertNil(fixture.session.userAlert)
    }

    func testGuestMetadataFallbackUsesMemberAccess() async throws {
        let persistence = makeInMemoryPersistence()
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
        let account = OneCartAccount(id: UUID(), displayName: "Sam")
        XCTAssertEqual(backend.access(for: space), .member)

        let members = try backend.familyMembers(for: space, account: account)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members[0].access, .member)
        XCTAssertTrue(members[0].isCurrentUser)
    }

    func test_REQ_SHARE_050_guestReturnsToPersonalWhenSharedGone() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")
        XCTAssertEqual(fixture.session.access, .member)

        try await fixture.session.repository.discardLocalSharedFamilySpace(id: fixture.sharedID)
        try await fixture.session.reactivatePersonalCartIfNeededForTesting()

        XCTAssertEqual(fixture.session.activeFamilySpace?.id, fixture.privateID)
        XCTAssertEqual(fixture.session.access, .owner)
        XCTAssertTrue(
            fixture.session.familySpaces.allSatisfy {
                fixture.session.persistence.scope(for: $0) == .private
            })
    }

    func test_REQ_SHARE_050_guestWhoseSharedCartDisappearsSeesRemovedMessageOnPersonalCart() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, fixture.sharedID)
        XCTAssertNil(fixture.session.sharedCartRemovedMessage)

        try await fixture.session.repository.discardLocalSharedFamilySpace(id: fixture.sharedID)
        await fixture.session.syncCart(reason: .cloudImport)

        XCTAssertEqual(
            fixture.session.sharedCartRemovedMessage,
            String(localized: "cart.shared_removed_message")
        )
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, fixture.privateID)
        XCTAssertEqual(fixture.session.access, .owner)
        XCTAssertFalse(fixture.session.lastActiveFamilyWasShared)
    }

    func test_REQ_SHARE_050_guestLeaveCartReturnsToPersonal() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")
        XCTAssertEqual(fixture.session.access, .member)

        await fixture.session.leaveCurrentFamily()

        XCTAssertEqual(fixture.session.activeFamilySpace?.id, fixture.privateID)
        XCTAssertEqual(fixture.session.access, .owner)
        XCTAssertTrue(
            fixture.session.familySpaces.allSatisfy {
                fixture.session.persistence.scope(for: $0) == .private
            })
        XCTAssertNil(fixture.session.userAlert)
        XCTAssertNil(fixture.session.sharedCartRemovedMessage)
        XCTAssertEqual(Set(fixture.session.products.map(\.displayName)), ["Private bread"])
    }

    func test_REQ_SHARE_050_cloudImportDuringLeaveDoesNotReportTheCartAsRemoved() async throws {
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk")
        let session = fixture.session

        async let leave: Void = session.leaveCurrentFamily()
        async let imports: Void = {
            for _ in 0..<5 {
                await session.syncCart(reason: .cloudImport)
                await Task.yield()
            }
        }()
        _ = await (leave, imports)
        await session.syncCart(reason: .cloudImport)

        XCTAssertEqual(session.activeFamilySpace?.id, fixture.privateID)
        XCTAssertNil(session.sharedCartRemovedMessage)
    }

    func test_REQ_SHARE_050_leaveRecoveryGivesUpAfterEightPasses() async throws {
        let clock = TestClock()
        let fixture = try await makeGuestFixture(sharedName: "Семейная", sharedProduct: "Milk", clock: clock.appClock)
        let session = fixture.session
        @MainActor final class Done {
            var value = false
        }
        let done = Done()

        // The shared cart never goes away here, so every recovery pass fails.
        session.leaveRecoveryTask = Task {
            await session.recoverAfterLeaveTimeout()
            done.value = true
        }
        for pass in 1...AppSession.leaveRecoveryPasses {
            let sleeping = await clock.waitForSleepers()
            XCTAssertTrue(sleeping, "Pass \(pass) waits one interval on the clock")
            XCTAssertFalse(done.value)
            clock.advance(by: AppSession.leaveRecoveryInterval)
        }
        for _ in 0..<10_000 where !done.value {
            await Task.yield()
        }

        XCTAssertTrue(done.value, "Recovery stops after the last pass instead of waiting again")
        XCTAssertEqual(clock.pendingSleepers, 0)
        XCTAssertTrue(session.familySpaces.contains { session.persistence.scope(for: $0) == .shared })
    }

    func testBenignShareLeaveFailures() {
        let zoneGone = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.zoneNotFound.rawValue
        )
        XCTAssertTrue(CloudKitUserFacingError.isBenignShareLeaveFailure(zoneGone))

        let unavailableMessage = "Item Unavailable. The owner stopped sharing, or your account doesn't have permission."
        let unavailable = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: unavailableMessage]
        )
        XCTAssertTrue(CloudKitUserFacingError.isBenignShareLeaveFailure(unavailable))
        XCTAssertTrue(CloudKitUserFacingError.isBenignShareAcceptFailure(unavailable))

        let permission = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.permissionFailure.rawValue
        )
        XCTAssertFalse(CloudKitUserFacingError.isBenignShareLeaveFailure(permission))
        XCTAssertTrue(CloudKitUserFacingError.isBenignShareAcceptFailure(permission))

        let network = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkFailure.rawValue
        )
        XCTAssertFalse(CloudKitUserFacingError.isBenignShareLeaveFailure(network))
    }

    private struct GuestFixture {
        var session: AppSession
        var privateID: UUID
        var sharedID: UUID
    }

    private func makeGuestFixture(
        sharedName: String,
        sharedProduct: String,
        clock: AppClock = .live
    ) async throws -> GuestFixture {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Sam")
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
            product.unit = "piece"
            product.category = ProductCategory.other.rawValue
            product.estimatedPrice = NSNumber(value: 0)
            product.isPurchased = NSNumber(value: false)
            product.createdAt = Date()
            product.updatedAt = Date()
            product.familySpace = space
            product.list = list
        }
        persistence.container.viewContext.processPendingChanges()
        defaults.set(privateID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults,
            clock: clock
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()

        return GuestFixture(session: session, privateID: privateID, sharedID: sharedID)
    }
}

extension AppSession {
    func reactivatePersonalCartIfNeededForTesting() async throws {
        guard let account else { return }
        try await household.reactivatePersonalCartIfNeeded(for: account)
    }
}
