import CoreData
@testable import OneCart
import XCTest

@MainActor
final class HouseholdEnsureTests: XCTestCase {
    func testEnsureHouseholdCreatesCartWhenEmpty() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Max")
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertNil(session.activeFamilySpace)
        XCTAssertTrue(session.familySpaces.isEmpty)

        await session.ensureHouseholdCartIfNeeded()

        XCTAssertNotNil(session.activeFamilySpace)
        XCTAssertFalse(session.householdCartBootstrapFailed)
        XCTAssertFalse(session.isEnsuringHouseholdCart)
    }

    func testEnsureHouseholdNoOpWhenActiveFamilyExists() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Max")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Cart",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(familyID.uuidString, forKey: "onecart.active-family-space-id.\(account.id.uuidString)")
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, familyID)

        await session.ensureHouseholdCartIfNeeded()

        XCTAssertEqual(session.activeFamilySpace?.id, familyID)
        XCTAssertFalse(session.householdCartBootstrapFailed)
    }

    func testEnsureHouseholdAdoptsSharedWhileOnPrivate() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Max")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let privateID = try await repository.createFamilySpace(
            name: "Private",
            cachedForUserID: account.id,
            isHouseholdDefault: true
        )
        defaults.set(
            privateID.uuidString,
            forKey: "onecart.active-family-space-id.\(account.id.uuidString)"
        )
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, privateID)

        let sharedID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = "Shared"
            space.createdAt = Date()
            space.updatedAt = Date()
            space.isHouseholdDefault = NSNumber(value: true)
        }
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }

        await session.ensureHouseholdCartIfNeeded()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(
            try session.persistence.scope(for: XCTUnwrap(session.activeFamilySpace)),
            .shared
        )
        XCTAssertEqual(session.familySpaces.map(\.id), [sharedID])
    }

    func testEnsureHouseholdSelectsNewestWithoutDeletingOtherSharedFamilies() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Max")

        let oldSharedID = UUID()
        let newSharedID = UUID()
        let older = Date().addingTimeInterval(-3600)
        let newer = Date()
        try await persistence.performBackgroundTask { context in
            for (id, name, stamp) in [
                (oldSharedID, "Old", older),
                (newSharedID, "New", newer),
            ] {
                let space = FamilySpace(context: context)
                try persistence.assign(space, to: .shared, in: context)
                space.id = id
                space.name = name
                space.createdAt = stamp
                space.updatedAt = stamp
                space.isHouseholdDefault = NSNumber(value: true)
            }
        }
        await persistence.container.viewContext.perform {
            persistence.container.viewContext.processPendingChanges()
        }
        defaults.set(
            oldSharedID.uuidString,
            forKey: "onecart.active-family-space-id.\(account.id.uuidString)"
        )
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        XCTAssertEqual(session.activeFamilySpace?.id, oldSharedID)

        await session.ensureHouseholdCartIfNeeded()

        XCTAssertEqual(session.activeFamilySpace?.id, newSharedID)
        let oldRequest = FamilySpace.fetchRequest()
        oldRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", oldSharedID as NSUUID),
            NSPredicate(format: "deletedAt == nil"),
        ])
        XCTAssertEqual(try session.persistence.container.viewContext.fetch(oldRequest).count, 1)
    }
}

@MainActor
final class PersonalCartRestoreBootstrapTests: XCTestCase {
    func testDelayedPrivateImportPreservesLocalItemsAndSelectsExistingCart() async throws {
        let fixture = try await makeFixture()
        let sourceID = try XCTUnwrap(fixture.session.activeFamilySpace?.id)
        let sourceListID = try XCTUnwrap(fixture.session.activeLists.first?.id)
        let localID = try await fixture.repository.addProduct(to: sourceListID, draft: productDraft(name: "Local"))
        let importedID = try await seedOlderCart(fixture)
        let importedListID = try XCTUnwrap(fixture.repository.fetchFamilySpace(id: importedID)?.activeLists.first?.id)
        let remoteID = try await fixture.repository.addProduct(to: importedListID, draft: productDraft(name: "Remote"))

        try await fixture.session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(fixture.session.activeFamilySpace?.id, importedID)
        XCTAssertEqual(Set(fixture.session.products.compactMap(\.id)), [localID, remoteID])
        XCTAssertEqual(try fixture.repository.fetchFamilySpace(id: sourceID)?.sortedProducts.first?.id, localID)
        XCTAssertNil(fixture.defaults.string(forKey: HouseholdCartCoordinator.provisionalFamilyKey(
            accountID: fixture.account.id
        )))
        XCTAssertFalse(fixture.session.isReconcilingPersonalCart)
    }

    func testProvisionalAndRestoredChoicesSurviveRestartAndPersonalFallback() async throws {
        let fixture = try await makeFixture(useFinishSetup: true)
        let sourceID = try XCTUnwrap(fixture.session.activeFamilySpace?.id)
        let restarted = AppSession(
            persistence: fixture.persistence,
            preferences: DevicePreferences(defaults: fixture.defaults),
            defaults: fixture.defaults
        )
        restarted.online = false
        try restarted.bootstrapTestingSession(account: fixture.account)
        let importedID = try await seedOlderCart(fixture)

        try await restarted.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(restarted.activeFamilySpace?.id, importedID)
        try restarted.reload(preferredFamilySpaceID: sourceID)
        try await restarted.household.reactivatePersonalCartIfNeeded(for: fixture.account)
        XCTAssertEqual(restarted.activeFamilySpace?.id, importedID)

        fixture.defaults.removeObject(forKey: restarted.activeFamilyKey(accountID: fixture.account.id))
        try restarted.reload(preferredFamilySpaceID: sourceID)
        try await restarted.finishFamilyCartSetup(for: fixture.account)
        XCTAssertEqual(restarted.activeFamilySpace?.id, importedID)
        XCTAssertNotNil(try fixture.repository.fetchFamilySpace(id: sourceID))
    }

    func testPartialImportAndPendingMutationsDeferPersonalSelection() async throws {
        let fixture = try await makeFixture()
        let sourceID = fixture.session.activeFamilySpace?.id
        let importedID = UUID()
        try await fixture.persistence.performBackgroundTask { context in
            let family = FamilySpace(context: context)
            try fixture.persistence.assign(family, to: .private, in: context)
            family.id = importedID
            family.name = "Importing"
            family.cachedForUserID = fixture.account.id
            family.createdAt = Date(timeIntervalSince1970: 1000)
        }

        try await fixture.session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sourceID)
        XCTAssertFalse(fixture.session.isReconcilingPersonalCart)
        try await fixture.persistence.performBackgroundTask { context in
            let family = try FamilySpaceRepository.requireFamilySpace(id: importedID, in: context)
            let list = ShoppingListEntity(context: context)
            try fixture.persistence.assign(list, toSameStoreAs: family, in: context)
            list.id = UUID()
            list.status = ShoppingListStatus.active.rawValue
            list.familySpace = family
        }
        fixture.session.pendingCartMutationCount = 1
        try await fixture.session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sourceID)
        fixture.session.pendingCartMutationCount = 0
        fixture.session.isBusy = true
        try await fixture.session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sourceID)

        fixture.session.isBusy = false
        try await fixture.session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(fixture.session.activeFamilySpace?.id, importedID)
    }

    func testFailedRestorePreservesSelectionAndPendingMarker() async throws {
        let fixture = try await makeFixture()
        let sourceID = fixture.session.activeFamilySpace?.id
        _ = try await seedOlderCart(fixture)
        let denied = FamilySpaceRepository(
            persistence: fixture.persistence,
            permissionAuthorizer: DenyAllPermissionAuthorizer()
        )
        let coordinator = HouseholdCartCoordinator(
            persistence: fixture.persistence,
            repository: denied,
            defaults: fixture.defaults
        )
        coordinator.bind(host: fixture.session)

        do {
            try await coordinator.reconcileProvisionalPersonalCartIfNeeded(for: fixture.account)
            XCTFail("Expected permissionDenied")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .permissionDenied)
        }

        XCTAssertEqual(fixture.session.activeFamilySpace?.id, sourceID)
        XCTAssertEqual(fixture.defaults.string(forKey: HouseholdCartCoordinator.provisionalFamilyKey(
            accountID: fixture.account.id
        )), sourceID?.uuidString)
        XCTAssertFalse(fixture.session.isReconcilingPersonalCart)
    }

    private struct Fixture {
        let persistence: PersistenceController
        let repository: FamilySpaceRepository
        let defaults: UserDefaults
        let account: OneCartAccount
        let session: AppSession
    }

    private func makeFixture(useFinishSetup: Bool = false) async throws -> Fixture {
        let (persistence, repository) = try await makeInMemoryRepository()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Restore")
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        session.online = false
        try session.bootstrapTestingSession(account: account)
        if useFinishSetup {
            try await session.finishFamilyCartSetup(for: account)
        } else {
            await session.ensureHouseholdCartIfNeeded()
        }
        XCTAssertEqual(defaults.string(forKey: HouseholdCartCoordinator.provisionalFamilyKey(accountID: account.id)),
                       session.activeFamilySpace?.id?.uuidString)
        return Fixture(persistence: persistence, repository: repository, defaults: defaults,
                       account: account, session: session)
    }

    private func seedOlderCart(_ fixture: Fixture) async throws -> UUID {
        try await fixture.repository.createFamilySpace(
            name: "Existing",
            createdAt: Date(timeIntervalSince1970: 1000),
            cachedForUserID: fixture.account.id,
            isHouseholdDefault: true
        )
    }
}
