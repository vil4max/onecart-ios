import CoreData
@testable import OneCart
import XCTest

@MainActor
final class FragileSyncOutcomeTests: XCTestCase {
    func testSyncCartPullFailureSetsFailedState() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        let account = OneCartAccount(id: UUID(), displayName: "Sync")
        try session.bootstrapTestingSession(account: account)

        session.cartSync.onHardRefresh = {
            throw NSError(
                domain: "FragileSync",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "refresh exploded"]
            )
        }

        await session.syncCart(reason: .pull)

        XCTAssertEqual(session.syncState, .failed)
        XCTAssertEqual(session.lastSyncError, "refresh exploded")
        XCTAssertEqual(session.alertMessage, "refresh exploded")
        XCTAssertNotEqual(
            session.alertMessage,
            RepositoryError.permissionDenied.localizedDescription
        )
    }

    func testSyncCartAppearFailureDoesNotPresentAlert() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: OneCartAccount(id: UUID(), displayName: "Sync"))

        session.cartSync.onHardRefresh = {
            throw NSError(
                domain: "FragileSync",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "appear refresh failed"]
            )
        }

        await session.syncCart(reason: .appear)

        XCTAssertEqual(session.syncState, .failed)
        XCTAssertEqual(session.lastSyncError, "appear refresh failed")
        XCTAssertNil(session.alertMessage)
    }

    func testSyncCartSuccessSetsSynchronized() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let session = AppSession(
            persistence: persistence,
            preferences: DevicePreferences(defaults: defaults),
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: OneCartAccount(id: UUID(), displayName: "Sync"))
        session.cartSync.onHardRefresh = {}

        await session.syncCart(reason: .pull)

        XCTAssertEqual(session.syncState, .synchronized)
        XCTAssertNil(session.lastSyncError)
    }
}
