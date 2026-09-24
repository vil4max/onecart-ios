import AuthenticationServices
import CoreData
@testable import OneCart
import XCTest

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func test_REQ_WIDGET_010_snapshotEncodingAndDecoding() throws {
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

    func testSnapshotStoreSaveAndLoad() throws {
        let store = try makeWidgetStore().store

        XCTAssertNil(store.loadSnapshot())

        let snapshot = WidgetCartSnapshot.placeholder
        store.save(snapshot: snapshot)

        let loaded = store.loadSnapshot()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.cartTitle, snapshot.cartTitle)
        XCTAssertEqual(loaded?.items.count, snapshot.items.count)
    }

    func testOptimisticSnapshotToggle() throws {
        let store = try makeWidgetStore().store

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

    func test_REQ_WIDGET_010_toggleWithPartialSnapshot_preservesHiddenPurchasedCount() throws {
        let store = try makeWidgetStore().store
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

    func test_REQ_WIDGET_010_emptyAndAllPurchasedHelpers() {
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

    func test_REQ_WIDGET_010_itemCategory_resolvesKnownRawAndFallsBackToOther() {
        let known = WidgetItemSnapshot(
            id: UUID(),
            name: "Milk",
            isPurchased: false,
            categoryRaw: ProductCategory.dairyEggs.rawValue
        )
        let unknown = WidgetItemSnapshot(
            id: UUID(),
            name: "Mystery",
            isPurchased: false,
            categoryRaw: "category-from-a-newer-app"
        )
        XCTAssertEqual(known.category, .dairyEggs)
        XCTAssertEqual(unknown.category, .other)
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
        let session = try makeTestSession(widgetStore: store)
        session.isReady = true
        session.preferences.theme = .light
        session.updateWidgetSnapshot(themeOverride: .dark)
        let loaded = store.loadSnapshot()
        XCTAssertEqual(loaded?.themeRaw, "dark")
        XCTAssertEqual(loaded?.preferredColorScheme, .dark)
    }

    @MainActor
    func testUpdateWidgetSnapshotBeforeReadyKeepsStoredSnapshot() throws {
        let store = try makeWidgetStore().store
        store.save(snapshot: .placeholder)
        let session = try makeTestSession(widgetStore: store)
        session.isReady = false
        session.updateWidgetSnapshot()
        XCTAssertEqual(store.loadSnapshot()?.totalCount, WidgetCartSnapshot.placeholder.totalCount)
        XCTAssertFalse(try XCTUnwrap(store.loadSnapshot()).isEmpty)

        session.isReady = true
        session.updateWidgetSnapshot()
        XCTAssertTrue(try XCTUnwrap(store.loadSnapshot()).isEmpty)
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
        let session = try makeTestSession(widgetStore: store)
        session.isReady = true
        session.preferences.accentColor = .sunset
        session.updateWidgetSnapshot(accentOverride: .ocean)
        let loaded = store.loadSnapshot()
        XCTAssertEqual(loaded?.accentColorRaw, "ocean")
        XCTAssertEqual(loaded?.accentColor, .ocean)
    }
}

extension WidgetSnapshotTests {
    func test_REQ_WIDGET_020_pendingPurchases_afterStoreRecreation_preservesCommandsUntilIndividualAcknowledgement(
    ) throws {
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

    func test_pendingPurchases_withBlockedQuarantineOrUnreadableEntry_keepsValidCommandsAvailable() throws {
        let fixture = try makeWidgetStore()
        let request = WidgetPurchaseRequest(accountID: UUID(), familyID: UUID(), productID: UUID(), isPurchased: true)
        try fixture.store.enqueuePurchase(request)
        let malformedURL = fixture.directory.appendingPathComponent("damaged.json")
        let quarantinedURL = malformedURL.appendingPathExtension("invalid")
        try Data("{invalid".utf8).write(to: malformedURL)
        try Data("older".utf8).write(to: quarantinedURL)
        // A directory named like a command fails with a read error, not a DecodingError.
        let unreadableURL = fixture.directory.appendingPathComponent("unreadable.json", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableURL, withIntermediateDirectories: true)

        XCTAssertEqual(try fixture.store.pendingPurchases(), [request])
        XCTAssertFalse(FileManager.default.fileExists(atPath: malformedURL.path))
        XCTAssertEqual(try Data(contentsOf: quarantinedURL), Data("{invalid".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unreadableURL.path))
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
    func test_REQ_WIDGET_020_performWidgetPurchase_savesRepositoryBeforeAcknowledging() async throws {
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

    func test_REQ_WIDGET_020_widgetRetry_afterNewerAppMutation_doesNotRestoreOldPurchasedState() async throws {
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

    func test_REQ_WIDGET_020_widgetPurchase_forTombstonedProduct_isAcknowledgedWithoutRestoringIt() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request()
        try await fixture.session.repository.deleteProduct(id: fixture.productID, familySpaceID: fixture.familyID)

        try await fixture.session.performWidgetPurchase(request)

        XCTAssertNil(fetchProduct(id: fixture.productID, repository: fixture.session.repository))
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_REQ_WIDGET_020_widgetPurchase_forDifferentAccountOrFamily_isRejectedBeforeEnqueue() async throws {
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

    func test_REQ_WIDGET_020_start_withDurableWidgetCommand_appliesItWithoutForegroundTransition() async throws {
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
    func makeWidgetSession(
        started: Bool = true,
        shoppingTripBackend: FakeShoppingTripBackend = FakeShoppingTripBackend()
    ) async throws -> WidgetSessionFixture {
        let (persistence, repository) = try await makeInMemoryRepository()
        let defaults = try makeDefaults()
        let store = try makeWidgetStore().store
        let account = OneCartAccount(id: OneCartStableID.uuid(for: "onecart.in-memory-user"), displayName: "Alex")
        let familyID = try await repository.createFamilySpace(
            name: "Personal", cachedForUserID: account.id, isHouseholdDefault: true
        )
        let listID = try XCTUnwrap(repository.fetchFamilySpace(id: familyID)?.activeLists.first?.id)
        let productID = try await repository.addProduct(to: listID, draft: productDraft())
        let session = try makeTestSession(
            persistence: persistence, defaults: defaults, appleSignIn: WidgetAppleSignIn(), widgetStore: store,
            shoppingTripBackend: shoppingTripBackend
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
private final class PurchaseReturnFlag {
    var value = false
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

private final class WidgetAppleSignIn: AppleSignInAuthenticating, @unchecked Sendable {
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

    func test_REQ_AUTH_060_signOut_clearsWidgetDataAndRejectsLateWidgetAction() async throws {
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

    func test_REQ_WIDGET_050_purchaseFromTheTripReachesItAndFinishesIt() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        fixture.session.updateWidgetSnapshot()

        await fixture.session.startShoppingTrip()
        XCTAssertTrue(fixture.session.isShoppingTripActive)
        XCTAssertEqual(backend.requested.first?.state.remainingCount, 1)
        XCTAssertEqual(backend.requested.first?.attributes.familyID, fixture.familyID)

        // The Live Activity's check button runs the same intent path as the widget.
        try await fixture.session.performWidgetPurchase(fixture.request())
        await fixture.session.shoppingTrip.settle()

        XCTAssertFalse(fixture.session.isShoppingTripActive)
        XCTAssertEqual(backend.ended.count, 1)
        XCTAssertEqual(backend.ended.first?.state?.isAllPurchased, true)
    }

    func test_REQ_WIDGET_050_lockScreenCheck_updatesTheTripBeforeReturning() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        fixture.session.updateWidgetSnapshot()
        await fixture.session.startShoppingTrip()

        // The system redraws the card when the intent returns, so the trip's own update
        // must finish first. A held ActivityKit call shows whether the intent waits for it.
        backend.holdsEnds = true
        // The purchase saves on a Core Data background context before it reaches the trip, so
        // main-actor yields alone can run out first on a loaded CI runner.
        let endHeld = expectation(description: "The trip's end reached ActivityKit")
        backend.onHeldEnd = { endHeld.fulfill() }
        let returned = PurchaseReturnFlag()
        let purchase = Task {
            try await fixture.session.performWidgetPurchase(fixture.request())
            returned.value = true
        }
        await fulfillment(of: [endHeld], timeout: 5)
        await backend.yield { returned.value }
        XCTAssertEqual(backend.heldEnds, 1)
        XCTAssertFalse(returned.value, "The check returned before the trip was updated")

        backend.releaseEnds()
        try await purchase.value
        XCTAssertEqual(backend.ended.map(\.state?.isAllPurchased), [true])
        XCTAssertFalse(fixture.session.isShoppingTripActive)
    }

    func test_REQ_WIDGET_060_signOut_endsTheShoppingTrip() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        await fixture.session.startShoppingTrip()
        XCTAssertEqual(backend.running.count, 1)

        fixture.session.signOut()
        await fixture.session.shoppingTrip.settle()

        XCTAssertFalse(fixture.session.isShoppingTripActive)
        XCTAssertTrue(backend.running.isEmpty)
        XCTAssertEqual(backend.ended.first?.dismissal, .immediate)
    }

    func test_REQ_WIDGET_060_signOutWhileTheTripIsStarting_endsIt() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        await fixture.session.startShoppingTrip()
        // A held end keeps the next start queued in the trip controller while no trip is active.
        backend.holdsEnds = true
        fixture.session.shoppingTrip.end()
        await backend.yield { backend.heldEnds == 1 }
        let starting = Task { await fixture.session.startShoppingTrip() }
        await backend.yield { false }
        XCTAssertFalse(fixture.session.isShoppingTripActive)

        fixture.session.signOut()
        backend.releaseEnds()
        await starting.value
        await fixture.session.shoppingTrip.settle()

        XCTAssertEqual(backend.requested.count, 2)
        XCTAssertTrue(backend.running.isEmpty)
        XCTAssertFalse(fixture.session.isShoppingTripActive)
    }

    /// A startup that fails (iCloud briefly unavailable, a store-load error) signs nobody out,
    /// so the trip stays for the retry that follows; REQ-WIDGET-060 ends it only on sign-out,
    /// deletion or a change of account or cart.
    func test_REQ_WIDGET_060_failedStartup_keepsTheRunningTrip() async throws {
        let backend = FakeShoppingTripBackend()
        let fixture = try await makeWidgetSession(shoppingTripBackend: backend)
        await fixture.session.startShoppingTrip()
        XCTAssertEqual(backend.running.count, 1)

        fixture.session.clearBootstrapAccount()
        await fixture.session.shoppingTrip.settle()

        XCTAssertEqual(backend.running.count, 1)
        XCTAssertTrue(backend.ended.isEmpty)
    }

    func test_REQ_WIDGET_060_launchWithoutSignedInAccount_endsTheLeftoverTrip() async throws {
        let leftover = ShoppingTripActivityRecord(id: "leftover", accountID: UUID(), familyID: UUID())
        let backend = FakeShoppingTripBackend(running: [leftover])
        let fixture = try await makeWidgetSession(started: false, shoppingTripBackend: backend)
        fixture.session.clearStoredAppleCredential()

        await fixture.session.start()
        await fixture.session.shoppingTrip.settle()

        XCTAssertTrue(fixture.session.needsWelcome)
        XCTAssertTrue(backend.running.isEmpty)
        XCTAssertEqual(backend.ended.map(\.id), ["leftover"])
        XCTAssertFalse(fixture.session.isShoppingTripActive)
    }

    func test_REQ_AUTH_070_deleteAccount_clearsWidgetSnapshotAndPendingPurchases() async throws {
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
