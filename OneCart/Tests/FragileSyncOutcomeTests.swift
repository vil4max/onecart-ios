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
        XCTAssertEqual(session.userAlert?.kind, .error)
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

    func testSyncCartCoalescesWithoutCancellingInFlight() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let cartSync = CartSyncService(persistence: persistence)
        var refreshCount = 0
        cartSync.onHardRefresh = {
            refreshCount += 1
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        async let first = cartSync.syncCart(reason: .cloudImport)
        try? await Task.sleep(nanoseconds: 10_000_000)
        async let second = cartSync.syncCart(reason: .pull)
        let outcomes = await (first, second)

        XCTAssertEqual(outcomes.0, .succeeded)
        XCTAssertEqual(outcomes.1, .succeeded)
        XCTAssertEqual(refreshCount, 2)
        XCTAssertEqual(cartSync.contentRevision, 2)
    }

    func test_coalescedPull_whenRefreshFails_returnsFailureToBothCallers() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let sync = CartSyncService(persistence: persistence)
        let started = expectation(description: "First refresh is suspended")
        let secondStarted = expectation(description: "Pull joins the active refresh")
        var release: CheckedContinuation<Void, Never>?
        var calls = 0
        sync.onHardRefresh = {
            calls += 1
            if calls == 1 {
                await withCheckedContinuation { continuation in
                    release = continuation
                    started.fulfill()
                }
            }
            throw NSError(domain: "Sync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Import failed"])
        }
        let first = Task { await sync.syncCart(reason: .cloudImport) }
        await fulfillment(of: [started], timeout: 2)
        let second = Task {
            secondStarted.fulfill()
            return await sync.syncCart(reason: .pull)
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        release?.resume()
        let outcomes = await (first.value, second.value)
        XCTAssertEqual(outcomes.0, .failed("Import failed"))
        XCTAssertEqual(outcomes.1, .failed("Import failed"))
        XCTAssertEqual(calls, 2)
    }

    func testSoftRefreshCartProductsBumpsRevision() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Soft")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Корзина",
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
        let list = try XCTUnwrap(session.activeLists.first)
        await session.addProduct(to: list, draft: productDraft(name: "Молоко"))
        let before = session.contentRevision

        session.softRefreshCartProducts()

        XCTAssertEqual(session.contentRevision, before + 1)
        XCTAssertEqual(session.products.first?.displayName, "Молоко")
    }

    func testCartContentStorePublishesAfterReload() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Content")
        let repository = FamilySpaceRepository(
            persistence: persistence,
            permissionAuthorizer: AllowAllPermissionAuthorizer()
        )
        let familyID = try await repository.createFamilySpace(
            name: "Корзина",
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
        let list = try XCTUnwrap(session.activeLists.first)
        await session.addProduct(to: list, draft: productDraft(name: "Хлеб"))
        XCTAssertFalse(session.products.isEmpty)

        try CartSyncService.resetViewContextAndRefetch(persistence: persistence) {
            try session.cartContent.reloadContent(familySpaceID: familyID)
        }
        XCTAssertFalse(session.products.isEmpty)
        XCTAssertEqual(session.products.first?.displayName, "Хлеб")
    }
}
