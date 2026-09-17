import AuthenticationServices
import CoreData
@testable import OneCart
import XCTest

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotEncodingAndDecoding() throws {
        let item1 = WidgetItemSnapshot(
            id: UUID(),
            name: "Молоко 3.2%",
            isPurchased: false,
            categoryRaw: ProductCategory.dairyEggs.rawValue,
            subtitle: "добавил(а) Саша"
        )
        let item2 = WidgetItemSnapshot(
            id: UUID(),
            name: "Хлеб",
            isPurchased: true,
            categoryRaw: ProductCategory.bakery.rawValue,
            subtitle: "в тележке"
        )

        let original = WidgetCartSnapshot(
            cartTitle: "Семья",
            totalCount: 2,
            purchasedCount: 1,
            isSyncing: true,
            lastUpdated: Date(),
            familyMemberCount: 2,
            activePartnerName: "Саша в магазине",
            items: [item1, item2]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetCartSnapshot.self, from: data)

        XCTAssertEqual(decoded.cartTitle, "Семья")
        XCTAssertEqual(decoded.totalCount, 2)
        XCTAssertEqual(decoded.purchasedCount, 1)
        XCTAssertEqual(decoded.remainingCount, 1)
        XCTAssertEqual(decoded.progress, 0.5, accuracy: 0.001)
        XCTAssertFalse(decoded.isEmpty)
        XCTAssertFalse(decoded.isAllPurchased)
        XCTAssertEqual(decoded.activePartnerName, "Саша в магазине")
        XCTAssertEqual(decoded.items.count, 2)
        XCTAssertEqual(decoded.items[0].name, "Молоко 3.2%")
        XCTAssertFalse(decoded.items[0].isPurchased)
        XCTAssertTrue(decoded.items[1].isPurchased)
    }

    func testSnapshotStoreSaveAndLoad() {
        let suite = "test.onecart.widget.\(UUID().uuidString)"
        let store = WidgetSnapshotStore(suiteName: suite)

        XCTAssertNil(store.loadSnapshot())

        let snapshot = WidgetCartSnapshot.placeholder
        store.save(snapshot: snapshot)

        let loaded = store.loadSnapshot()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.cartTitle, snapshot.cartTitle)
        XCTAssertEqual(loaded?.items.count, snapshot.items.count)
    }

    func testOptimisticSnapshotToggle() {
        let suite = "test.onecart.widget.\(UUID().uuidString)"
        let store = WidgetSnapshotStore(suiteName: suite)

        let testID = UUID()
        let snapshot = WidgetCartSnapshot(
            cartTitle: "Тест",
            totalCount: 2,
            purchasedCount: 0,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            activePartnerName: nil,
            items: [
                WidgetItemSnapshot(id: testID, name: "Яблоки", isPurchased: false, categoryRaw: "produce"),
                WidgetItemSnapshot(id: UUID(), name: "Сыр", isPurchased: false, categoryRaw: "dairyEggs"),
            ]
        )
        store.save(snapshot: snapshot)

        let didToggle = store.toggleItem(id: testID)
        XCTAssertTrue(didToggle)

        let updated = store.loadSnapshot()
        XCTAssertEqual(updated?.purchasedCount, 1)
        let toggledItem = updated?.items.first(where: { $0.id == testID })
        XCTAssertEqual(toggledItem?.isPurchased, true)
    }

    func test_toggleWithPartialSnapshot_preservesHiddenPurchasedCount() {
        let suite = "test.onecart.widget.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(suiteName: suite)
        let id = UUID()
        store.save(snapshot: WidgetCartSnapshot(
            cartTitle: "Family", totalCount: 15, purchasedCount: 10,
            isSyncing: false, lastUpdated: Date(), familyMemberCount: 1,
            items: [WidgetItemSnapshot(id: id, name: "Milk", isPurchased: false, categoryRaw: "dairyEggs")]
        ))
        XCTAssertTrue(store.toggleItem(id: id))
        XCTAssertEqual(store.loadSnapshot()?.purchasedCount, 11)
        XCTAssertEqual(store.loadSnapshot()?.remainingCount, 4)
        XCTAssertTrue(store.toggleItem(id: id))
        XCTAssertEqual(store.loadSnapshot()?.purchasedCount, 10)
    }

    func testEmptyAndAllPurchasedHelpers() {
        let empty = WidgetCartSnapshot.empty
        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.isAllPurchased)
        XCTAssertEqual(empty.remainingCount, 0)
        XCTAssertEqual(empty.progress, 0.0)

        let allPurchased = WidgetCartSnapshot(
            cartTitle: "Всё куплено",
            totalCount: 3,
            purchasedCount: 3,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            items: []
        )
        XCTAssertFalse(allPurchased.isEmpty)
        XCTAssertTrue(allPurchased.isAllPurchased)
        XCTAssertEqual(allPurchased.remainingCount, 0)
        XCTAssertEqual(allPurchased.progress, 1.0)
    }

    func testThemeRoundtripAndColorScheme() throws {
        let darkSnapshot = WidgetCartSnapshot(
            cartTitle: "Dark Cart",
            totalCount: 1,
            purchasedCount: 0,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            activePartnerName: nil,
            themeRaw: "dark",
            items: []
        )
        XCTAssertEqual(darkSnapshot.preferredColorScheme, .dark)

        let encoded = try JSONEncoder().encode(darkSnapshot)
        let decoded = try JSONDecoder().decode(WidgetCartSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.themeRaw, "dark")
        XCTAssertEqual(decoded.preferredColorScheme, .dark)

        let lightSnapshot = WidgetCartSnapshot(
            cartTitle: "Light Cart",
            totalCount: 1,
            purchasedCount: 0,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            activePartnerName: nil,
            themeRaw: "light",
            items: []
        )
        XCTAssertEqual(lightSnapshot.preferredColorScheme, .light)

        let systemSnapshot = WidgetCartSnapshot(
            cartTitle: "System Cart",
            totalCount: 1,
            purchasedCount: 0,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            activePartnerName: nil,
            themeRaw: "system",
            items: []
        )
        XCTAssertNil(systemSnapshot.preferredColorScheme)
    }

    @MainActor
    func testUpdateWidgetSnapshotThemeOverride() throws {
        let store = try makeWidgetStore().store
        let session = AppSession(widgetStore: store)
        session.isReady = true
        session.preferences.theme = .light
        session.updateWidgetSnapshot(themeOverride: .dark)
        let loaded = store.loadSnapshot()
        XCTAssertEqual(loaded?.themeRaw, "dark")
        XCTAssertEqual(loaded?.preferredColorScheme, .dark)
    }

    func testAccentColorRoundtripAndFallback() throws {
        let berrySnapshot = WidgetCartSnapshot(
            cartTitle: "Berry Cart",
            totalCount: 1,
            purchasedCount: 0,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            activePartnerName: nil,
            themeRaw: nil,
            accentColorRaw: "berry",
            items: []
        )
        XCTAssertEqual(berrySnapshot.accentColor, .berry)

        let encoded = try JSONEncoder().encode(berrySnapshot)
        let decoded = try JSONDecoder().decode(WidgetCartSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.accentColorRaw, "berry")
        XCTAssertEqual(decoded.accentColor, .berry)

        // Snapshot without accentColorRaw (legacy) falls back gracefully to emerald
        let legacyJson = Data("""
        {
            "cartTitle": "Legacy",
            "totalCount": 0,
            "purchasedCount": 0,
            "isSyncing": false,
            "lastUpdated": 0,
            "familyMemberCount": 1,
            "items": []
        }
        """.utf8)
        let legacyDecoded = try JSONDecoder().decode(WidgetCartSnapshot.self, from: legacyJson)
        XCTAssertNil(legacyDecoded.accentColorRaw)
        let expectedFallback = AppAccentColor(
            rawValue: OneCartAppGroup.defaults?.string(forKey: "onecart.accent-color") ?? ""
        ) ?? .emerald
        XCTAssertEqual(legacyDecoded.accentColor, expectedFallback)
    }

    @MainActor
    func testUpdateWidgetSnapshotAccentOverride() throws {
        let store = try makeWidgetStore().store
        let session = AppSession(widgetStore: store)
        session.isReady = true
        session.preferences.accentColor = .sunset
        session.updateWidgetSnapshot(accentOverride: .ocean)
        let loaded = store.loadSnapshot()
        XCTAssertEqual(loaded?.accentColorRaw, "ocean")
        XCTAssertEqual(loaded?.accentColor, .ocean)
    }
}

extension WidgetSnapshotTests {
    func test_pendingPurchases_afterStoreRecreation_preservesCommandsUntilIndividualAcknowledgement() throws {
        let fixture = try makeWidgetStore()
        let first = WidgetPurchaseRequest(accountID: UUID(), familyID: UUID(), productID: UUID(), isPurchased: true)
        let second = WidgetPurchaseRequest(
            accountID: first.accountID, familyID: first.familyID, productID: first.productID,
            isPurchased: false, createdAt: first.createdAt.addingTimeInterval(1)
        )
        try fixture.store.enqueuePurchase(first)
        try fixture.store.enqueuePurchase(second)
        let reopened = WidgetSnapshotStore(suiteName: fixture.suite, pendingDirectoryURL: fixture.directory)

        XCTAssertEqual(try reopened.pendingPurchases(), [first, second])
        try reopened.enqueuePurchase(WidgetPurchaseRequest(
            id: first.id, accountID: first.accountID, familyID: first.familyID,
            productID: first.productID, isPurchased: true, createdAt: second.createdAt
        ))
        XCTAssertEqual(try reopened.pendingPurchases(), [first, second])
        try reopened.acknowledgePurchase(id: first.id)
        XCTAssertEqual(try fixture.store.pendingPurchases(), [second])
    }

    func test_pendingPurchases_withMalformedFile_keepsValidCommandsAvailable() throws {
        let fixture = try makeWidgetStore()
        let request = WidgetPurchaseRequest(accountID: UUID(), familyID: UUID(), productID: UUID(), isPurchased: true)
        try fixture.store.enqueuePurchase(request)
        let malformedURL = fixture.directory.appendingPathComponent("damaged.json")
        try Data("{invalid".utf8).write(to: malformedURL)

        XCTAssertEqual(try fixture.store.pendingPurchases(), [request])
        XCTAssertFalse(FileManager.default.fileExists(atPath: malformedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: malformedURL.appendingPathExtension("invalid").path))
        XCTAssertEqual(try fixture.store.pendingPurchases(), [request])
    }
}

private extension XCTestCase {
    func makeWidgetStore() throws -> (store: WidgetSnapshotStore, suite: String, directory: URL) {
        let suite = "OneCartWidgetTests.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return (WidgetSnapshotStore(suiteName: suite, pendingDirectoryURL: directory), suite, directory)
    }
}

@MainActor
extension WidgetSnapshotTests {
    func test_performWidgetPurchase_savesRepositoryBeforeAcknowledging() async throws {
        let fixture = try await makeWidgetSession()
        fixture.session.preferences.participantDisplayName = "Local nickname"
        let request = fixture.request()

        try await fixture.session.performWidgetPurchase(request)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.session.repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedAt, request.createdAt)
        XCTAssertEqual(product.purchasedByName, "Local nickname")
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
        XCTAssertEqual(fixture.store.loadSnapshot()?.accountID, fixture.accountID)
        XCTAssertEqual(fixture.store.loadSnapshot()?.familyID, fixture.familyID)
        XCTAssertEqual(fixture.store.loadSnapshot()?.purchasedCount, 1)
        XCTAssertEqual(fixture.session.pendingCartMutationCount, 0)
    }

    func test_widgetRetry_afterNewerAppMutation_doesNotRestoreOldPurchasedState() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request()
        try fixture.store.enqueuePurchase(request)
        try await fixture.session.repository.setPurchased(
            id: request.productID, familySpaceID: request.familyID, isPurchased: true,
            participantDisplayName: "Alex", purchasedAt: request.createdAt
        )
        // Simulate a saved command whose acknowledgement was interrupted, followed by an app edit.
        try await fixture.session.repository.togglePurchased(
            id: request.productID, familySpaceID: request.familyID, participantDisplayName: "Alex"
        )

        try await fixture.session.performWidgetPurchase(request)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.session.repository))
        XCTAssertFalse(product.isPurchasedValue)
        XCTAssertNil(product.purchasedAt)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_missingProduct_retainsOrderedCommandsWithoutBlockingAnotherProduct() async throws {
        let fixture = try await makeWidgetSession()
        let missingID = UUID()
        let familyID = fixture.familyID
        let first = fixture.request(productID: missingID)
        let second = fixture.request(
            productID: missingID, isPurchased: false, createdAt: first.createdAt.addingTimeInterval(1)
        )
        do {
            try await fixture.session.performWidgetPurchase(first)
            XCTFail("A product that has not arrived must remain pending")
        } catch {
            XCTAssertEqual(try fixture.store.pendingPurchases(), [first])
        }
        try fixture.store.enqueuePurchase(second)

        try await fixture.session.performWidgetPurchase(fixture.request())

        XCTAssertEqual(try fixture.store.pendingPurchases(), [first, second])
        XCTAssertTrue(try XCTUnwrap(fetchProduct(
            id: fixture.productID, repository: fixture.session.repository
        )).isPurchasedValue)
        try await fixture.session.repository.addProduct(
            to: fixture.listID, id: missingID, draft: productDraft(name: "Late import")
        )
        try await fixture.session.persistence.performBackgroundTask { context in
            let imported = try XCTUnwrap(FamilySpaceRepository.fetchProduct(
                id: missingID, familySpaceID: familyID, in: context
            ))
            imported.updatedAt = first.createdAt.addingTimeInterval(-1)
        }

        await fixture.session.drainWidgetPendingToggles()

        let imported = try XCTUnwrap(fetchProduct(id: missingID, repository: fixture.session.repository))
        XCTAssertFalse(imported.isPurchasedValue)
        XCTAssertEqual(imported.updatedAt, second.createdAt)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_widgetPurchase_forTombstonedProduct_isAcknowledgedWithoutRestoringIt() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request()
        try await fixture.session.repository.deleteProduct(id: fixture.productID, familySpaceID: fixture.familyID)

        try await fixture.session.performWidgetPurchase(request)

        XCTAssertNil(fetchProduct(id: fixture.productID, repository: fixture.session.repository))
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_widgetPurchase_forDifferentAccountOrFamily_isRejectedBeforeEnqueue() async throws {
        let fixture = try await makeWidgetSession()
        let requests = [
            WidgetPurchaseRequest(
                accountID: UUID(), familyID: fixture.familyID, productID: fixture.productID, isPurchased: true
            ),
            WidgetPurchaseRequest(
                accountID: fixture.accountID, familyID: UUID(), productID: fixture.productID, isPurchased: true
            ),
        ]
        for request in requests {
            do {
                try await fixture.session.performWidgetPurchase(request)
                XCTFail("A widget action must match the active account and family")
            } catch {
                XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
            }
        }
        XCTAssertFalse(try XCTUnwrap(fetchProduct(
            id: fixture.productID, repository: fixture.session.repository
        )).isPurchasedValue)
    }

    func test_start_withDurableWidgetCommand_appliesItWithoutForegroundTransition() async throws {
        let fixture = try await makeWidgetSession(started: false)
        let purchasedAt = Date().addingTimeInterval(-86400)
        let request = fixture.request(createdAt: purchasedAt)
        try await fixture.session.persistence.performBackgroundTask { context in
            let product = try XCTUnwrap(FamilySpaceRepository.fetchProduct(
                id: request.productID, familySpaceID: request.familyID, in: context
            ))
            product.updatedAt = purchasedAt.addingTimeInterval(-1)
        }
        try fixture.store.enqueuePurchase(request)
        XCTAssertNil(fixture.session.account)

        await fixture.session.start()

        XCTAssertEqual(fixture.session.account?.id, fixture.accountID)
        let product = try XCTUnwrap(fetchProduct(
            id: fixture.productID, repository: fixture.session.repository
        ))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedAt, purchasedAt)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_concurrentWidgetRequests_completeWithLatestDesiredState() async throws {
        let fixture = try await makeWidgetSession()
        let first = fixture.request()
        let second = fixture.request(isPurchased: false, createdAt: first.createdAt.addingTimeInterval(1))

        async let firstResult: Void = fixture.session.performWidgetPurchase(first)
        async let secondResult: Void = fixture.session.performWidgetPurchase(second)
        _ = try await (firstResult, secondResult)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.session.repository))
        XCTAssertFalse(product.isPurchasedValue)
        XCTAssertEqual(product.updatedAt, second.createdAt)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
        XCTAssertEqual(fixture.session.pendingCartMutationCount, 0)
    }
}

@MainActor
private extension XCTestCase {
    func makeWidgetSession(started: Bool = true) async throws -> WidgetSessionFixture {
        let (persistence, repository) = try await makeInMemoryRepository()
        let defaults = try makeDefaults()
        let store = try makeWidgetStore().store
        let account = OneCartAccount(id: OneCartStableID.uuid(for: "onecart.in-memory-user"), displayName: "Alex")
        let familyID = try await repository.createFamilySpace(
            name: "Personal", cachedForUserID: account.id, isHouseholdDefault: true
        )
        let listID = try XCTUnwrap(repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id)
        let productID = try await repository.addProduct(to: listID, draft: productDraft())
        let session = AppSession(
            persistence: persistence, defaults: defaults, appleSignIn: WidgetAppleSignIn(), widgetStore: store
        )
        if started {
            try session.bootstrapTestingSession(account: account)
            session.started = true
            session.needsWelcome = false
        }
        return WidgetSessionFixture(
            session: session, store: store, accountID: account.id,
            familyID: familyID, listID: listID, productID: productID
        )
    }
}

@MainActor
private struct WidgetSessionFixture {
    let session: AppSession
    let store: WidgetSnapshotStore
    let accountID: UUID
    let familyID: UUID
    let listID: UUID
    let productID: UUID

    func request(
        productID: UUID? = nil,
        isPurchased: Bool = true,
        createdAt: Date = Date()
    ) -> WidgetPurchaseRequest {
        WidgetPurchaseRequest(
            accountID: accountID, familyID: familyID, productID: productID ?? self.productID,
            isPurchased: isPurchased, createdAt: createdAt
        )
    }
}

private final class WidgetAppleSignIn: AppleSignInAuthenticating {
    private var credential: AppleSignInCredential? = AppleSignInCredential(
        userID: "widget-user", email: nil, givenName: "Alex", familyName: nil
    )

    func storedCredential() -> AppleSignInCredential? {
        credential
    }

    func save(_ credential: AppleSignInCredential) {
        self.credential = credential
    }

    func clearCredential() {
        credential = nil
    }

    func credentialState(for _: String) async -> AppleSignInCredentialState {
        .authorized
    }

    func signIn() async throws -> AppleSignInCredential {
        try XCTUnwrap(credential)
    }

    func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
        try XCTUnwrap(credential)
    }
}

@MainActor
final class WidgetPrivacyCleanupTests: XCTestCase {
    func test_clear_removesWidgetSnapshotAndPendingPurchases() throws {
        let fixture = try makeWidgetStore()
        fixture.store.save(snapshot: .placeholder)
        try fixture.store.enqueuePurchase(WidgetPurchaseRequest(
            accountID: UUID(), familyID: UUID(), productID: UUID(), isPurchased: true
        ))

        try fixture.store.clear()

        XCTAssertTrue(fixture.store.loadSnapshot()?.isEmpty ?? true)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_signOut_clearsWidgetDataAndRejectsLateWidgetAction() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request()
        try fixture.store.enqueuePurchase(request)
        fixture.session.updateWidgetSnapshot()
        XCTAssertFalse(try XCTUnwrap(fixture.store.loadSnapshot()).isEmpty)

        fixture.session.signOut()

        XCTAssertNil(fixture.session.account)
        XCTAssertTrue(fixture.store.loadSnapshot()?.isEmpty ?? true)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
        do {
            try await fixture.session.performWidgetPurchase(request)
            XCTFail("A stale widget must not enqueue purchases after sign-out")
        } catch {
            XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
        }
    }

    func test_deleteAccount_clearsWidgetSnapshotAndPendingPurchases() async throws {
        let fixture = try await makeWidgetSession()
        try fixture.store.enqueuePurchase(fixture.request())
        fixture.session.updateWidgetSnapshot()
        XCTAssertFalse(try XCTUnwrap(fixture.store.loadSnapshot()).isEmpty)

        await fixture.session.deleteAccount()

        XCTAssertNil(fixture.session.account)
        XCTAssertTrue(fixture.store.loadSnapshot()?.isEmpty ?? true)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }
}
