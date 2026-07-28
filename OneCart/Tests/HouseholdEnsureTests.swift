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
}
