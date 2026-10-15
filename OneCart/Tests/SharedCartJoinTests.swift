import CoreData
@testable import OneCart
import XCTest

@MainActor
final class SharedCartJoinTests: XCTestCase, SharedCartSeeding {
    func test_REQ_SHARE_090_emptyPrivateAutoAdoptsShared() async throws {
        let fixture = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            sharedProduct: "Test 1"
        )
        let (session, privateID, sharedID) = (fixture.session, fixture.privateID, fixture.sharedID)

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
        XCTAssertNotNil(
            try session.persistence.container.viewContext.fetch(
                familySpaceRequest(id: privateID)
            ).first)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_privateContentIsNotMergedIntoSharedOnAdopt() async throws {
        let fixture = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            privateProduct: "Мой хлеб",
            sharedProduct: "Test 1"
        )
        let (session, privateID, sharedID) = (fixture.session, fixture.privateID, fixture.sharedID)

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
        XCTAssertNotNil(
            try session.persistence.container.viewContext.fetch(
                familySpaceRequest(id: privateID)
            ).first)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_ensureHouseholdAdoptsSharedEvenWhenPrivateActive() async throws {
        let fixture = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            sharedProduct: "Test 1"
        )
        let (session, privateID, sharedID) = (fixture.session, fixture.privateID, fixture.sharedID)
        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])

        await session.ensureHouseholdCartIfNeeded()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.access, .member)
        XCTAssertNotNil(
            try session.persistence.container.viewContext.fetch(
                familySpaceRequest(id: privateID)
            ).first)
    }

    func test_REQ_SHARE_090_reloadPrefersSharedOverStoredPrivate() async throws {
        let fixture = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            sharedProduct: "Test 1"
        )
        let (session, sharedID) = (fixture.session, fixture.sharedID)

        try session.reload(preferredFamilySpaceID: sharedID)

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
    }

    func test_REQ_SHARE_090_reloadSwitchesToSharedWhenSharedAppearsLater() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let privateID = try await repository.createFamilySpace(
            name: "Моя",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(privateID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, privateID)

        let sharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Семейная",
            productName: "Test 1"
        )
        try session.reload(preferredFamilySpaceID: privateID)

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_alreadyOnSharedStaysShared() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let sharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Семейная",
            productName: "Test 1"
        )
        defaults.set(sharedID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Test 1"])
    }

    func test_REQ_SHARE_090_adoptSelectsSharedWithoutMergingPrivateContent() async throws {
        let fixture = try await makeJoinFixture(
            privateName: "Моя",
            sharedName: "Семейная",
            privateProduct: "Мой хлеб",
            sharedProduct: nil,
            includeSharedList: false
        )
        let (session, privateID, sharedID) = (fixture.session, fixture.privateID, fixture.sharedID)

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(
            session.activeFamilySpace?.id,
            sharedID,
            "Invitee must join shared cart; personal stays hidden on disk"
        )
        XCTAssertEqual(
            persistenceScope(for: session.activeFamilySpace, in: session.persistence),
            .shared
        )
        XCTAssertNotNil(
            try session.persistence.container.viewContext.fetch(
                familySpaceRequest(id: privateID)
            ).first)
        XCTAssertTrue(session.products.isEmpty)
    }

    func test_REQ_SYNC_040_acceptSelectsNewestSharedWithoutDeletingOtherFamilies() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )

        let privateID = try await repository.createFamilySpace(
            name: "Моя",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        let privateListID = try XCTUnwrap(
            repository.fetchFamilySpace(id: privateID)?.activeLists.first?.id
        )
        _ = try await repository.addProduct(
            to: privateListID,
            draft: productDraft(name: "Мой хлеб")
        )

        let oldSharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Старая семейная",
            productName: "Old",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        let newSharedID = try await seedSharedCart(
            persistence: persistence,
            name: "Новая семейная",
            productName: "New",
            updatedAt: Date()
        )
        defaults.set(oldSharedID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, oldSharedID)
        XCTAssertEqual(session.access, .member)

        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, newSharedID)
        XCTAssertEqual(session.access, .member)
        XCTAssertNotNil(
            try session.persistence.container.viewContext.fetch(
                familySpaceRequest(id: oldSharedID)
            ).first)
        let oldFamily = try XCTUnwrap(repository.fetchFamilySpace(id: oldSharedID))
        XCTAssertNil(oldFamily.deletedAt)
        XCTAssertEqual(oldFamily.activeLists.flatMap(\.sortedProducts).map(\.displayName), ["Old"])
        XCTAssertNotNil(
            try session.persistence.container.viewContext.fetch(
                familySpaceRequest(id: privateID)
            ).first)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["New"])
    }

    func test_REQ_SYNC_030_refreshFromServerPicksUpToggledPurchasedState() async throws {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Семейная",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        let listID = try XCTUnwrap(
            repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id
        )
        let productID = try await repository.addProduct(
            to: listID,
            draft: productDraft(name: "Test 1")
        )
        defaults.set(familyID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.products.filter(\.isPurchasedValue).count, 0)

        try await repository.togglePurchased(id: productID, participantDisplayName: "Анна")
        await session.refreshFromServer()

        XCTAssertEqual(session.products.filter(\.isPurchasedValue).count, 1)
        let refreshed = try XCTUnwrap(session.products.first { $0.id == productID })
        XCTAssertTrue(refreshed.isPurchasedValue)
        XCTAssertEqual(refreshed.purchasedByName, "Анна")
        XCTAssertEqual(
            session.products(inListID: listID).filter(\.isPurchasedValue).count,
            1
        )
    }

    private func makeJoinFixture(
        privateName: String,
        sharedName: String,
        privateProduct: String? = nil,
        sharedProduct: String? = nil,
        includeSharedList: Bool = true
    ) async throws -> JoinFixture {
        let persistence = makeInMemoryPersistence()
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
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
            productName: sharedProduct,
            includeList: includeSharedList
        )
        defaults.set(privateID.uuidString, forKey: AppSession.activeFamilyKey(accountID: account.id))

        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        persistence.container.viewContext.processPendingChanges()
        return JoinFixture(session: session, account: account, privateID: privateID, sharedID: sharedID)
    }

    private func persistenceScope(
        for space: FamilySpace?,
        in persistence: PersistenceController
    ) -> PersistentStoreScope? {
        guard let space else { return nil }
        return persistence.scope(for: space)
    }
}

private struct JoinFixture {
    let session: AppSession
    let account: OneCartAccount
    let privateID: UUID
    let sharedID: UUID
}
