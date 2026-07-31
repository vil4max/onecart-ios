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

        await session.ensureHouseholdCartIfNeeded()

        XCTAssertEqual(session.activeFamilySpace?.id, sharedID)
        XCTAssertEqual(
            session.persistence.scope(for: try XCTUnwrap(session.activeFamilySpace)),
            .shared
        )
    }

    func testEnsureHouseholdConsolidatesStaleGuestShareOntoNewest() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Max")

        let oldSharedID = UUID()
        let newSharedID = UUID()
        let older = Date().addingTimeInterval(-3_600)
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
        XCTAssertTrue(try session.persistence.container.viewContext.fetch(oldRequest).isEmpty)
    }
}
