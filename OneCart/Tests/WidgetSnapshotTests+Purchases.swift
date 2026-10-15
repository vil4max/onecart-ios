import AuthenticationServices
import CoreData
@testable import OneCart
import XCTest

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

    func test_REQ_WIDGET_010_snapshotShowsTheListTheCartScreenShowsWhenANewerListExists() async throws {
        let fixture = try await makeWidgetSession()
        let persistence = fixture.session.persistence
        let familyID = fixture.familyID
        try await persistence.performBackgroundTask { context in
            let request = FamilySpace.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", familyID as NSUUID)
            guard let space = try context.fetch(request).first else { throw RepositoryError.familySpaceNotFound }
            let store = StoreEntity(context: context)
            try persistence.assign(store, toSameStoreAs: space, in: context)
            store.id = UUID()
            store.name = "Corner shop"
            store.familySpace = space

            // A legacy store-bound list, updated after the general list, sorts first among active lists.
            let list = ShoppingListEntity(context: context)
            try persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = UUID()
            list.title = "Corner shop"
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = Date()
            list.updatedAt = Date().addingTimeInterval(60)
            list.familySpace = space
            list.store = store

            let product = ProductEntity(context: context)
            try persistence.assign(product, toSameStoreAs: space, in: context)
            product.id = UUID()
            product.name = "Store bread"
            product.quantity = NSNumber(value: 1)
            product.unit = "piece"
            product.category = ProductCategory.bakery.rawValue
            product.estimatedPrice = NSNumber(value: 0)
            product.isPurchased = NSNumber(value: false)
            product.createdAt = Date()
            product.updatedAt = Date()
            product.familySpace = space
            product.list = list
            product.store = store
        }
        persistence.container.viewContext.processPendingChanges()
        try fixture.session.reload()
        XCTAssertEqual(fixture.session.activeLists.count, 2)
        XCTAssertNotNil(fixture.session.activeLists.first?.store)

        let snapshot = fixture.session.makeWidgetSnapshot(accent: fixture.session.preferences.accentColor)

        XCTAssertEqual(ShoppingListEntity.primaryList(in: fixture.session.activeLists)?.id, fixture.listID)
        XCTAssertEqual(snapshot.items.map(\.id), [fixture.productID])
        XCTAssertEqual(snapshot.totalCount, 1)
    }

    func test_REQ_WIDGET_020_categoryRefinementAfterAQueuedPurchaseDoesNotDropIt() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request(createdAt: Date())
        try fixture.store.enqueuePurchase(request)
        // The classifier finishes after the widget tap was queued.
        try await fixture.session.repository.updateProductCategory(
            id: fixture.productID, familySpaceID: fixture.familyID, category: .dairyEggs
        )

        try await fixture.session.performWidgetPurchase(request)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.session.repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.categoryValue, .dairyEggs)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_REQ_WIDGET_020_renameAfterAQueuedPurchaseDoesNotDropIt() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request(createdAt: Date())
        try fixture.store.enqueuePurchase(request)
        try await fixture.session.repository.updateProduct(
            id: fixture.productID, familySpaceID: fixture.familyID, draft: productDraft(name: "Oat milk")
        )

        try await fixture.session.performWidgetPurchase(request)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.session.repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.displayName, "Oat milk")
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
        XCTAssertTrue(
            try XCTUnwrap(
                fetchProduct(
                    id: fixture.productID, repository: fixture.session.repository
                )
            ).isPurchasedValue)
        try await fixture.session.repository.addProduct(
            to: fixture.listID, id: missingID, draft: productDraft(name: "Late import")
        )
        try await fixture.session.persistence.performBackgroundTask { context in
            let imported = try XCTUnwrap(
                FamilySpaceRepository.fetchProduct(
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
        XCTAssertFalse(
            try XCTUnwrap(
                fetchProduct(
                    id: fixture.productID, repository: fixture.session.repository
                )
            ).isPurchasedValue)
    }

    func test_REQ_WIDGET_020_start_withDurableWidgetCommand_appliesItWithoutForegroundTransition() async throws {
        let fixture = try await makeWidgetSession(started: false)
        let purchasedAt = Date().addingTimeInterval(-86400)
        let request = fixture.request(createdAt: purchasedAt)
        try await fixture.session.persistence.performBackgroundTask { context in
            let product = try XCTUnwrap(
                FamilySpaceRepository.fetchProduct(
                    id: request.productID, familySpaceID: request.familyID, in: context
                ))
            product.updatedAt = purchasedAt.addingTimeInterval(-1)
        }
        try fixture.store.enqueuePurchase(request)
        XCTAssertNil(fixture.session.account)

        await fixture.session.start()

        XCTAssertEqual(fixture.session.account?.id, fixture.accountID)
        let product = try XCTUnwrap(
            fetchProduct(
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

    func test_REQ_WIDGET_020_purchaseIntentWithMalformedIDThrowsBeforeReachingTheSession() async throws {
        let valid = UUID().uuidString
        let intents = [
            ToggleProductPurchasedIntent(productID: "not-a-uuid", accountID: valid, familyID: valid, isPurchased: true),
            ToggleProductPurchasedIntent(productID: valid, accountID: "", familyID: valid, isPurchased: true),
            ToggleProductPurchasedIntent(productID: valid, accountID: valid, familyID: "family", isPurchased: false),
        ]

        for intent in intents {
            do {
                _ = try await intent.perform()
                XCTFail("A malformed purchase request must be rejected")
            } catch {
                guard case WidgetPurchaseError.invalidRequest = error else {
                    XCTFail("Unexpected error \(error)")
                    continue
                }
            }
        }
        #if DEBUG
            XCTAssertFalse(OneCartAppComposition.didBuildSession, "The rejection must not build the app session")
        #endif
    }

    func test_REQ_WIDGET_020_widgetIntentsAreNotOfferedInShortcuts() {
        XCTAssertFalse(ToggleProductPurchasedIntent.isDiscoverable)
        XCTAssertFalse(EndShoppingTripIntent.isDiscoverable)
    }
}

// Shared with WidgetPrivacyCleanupTests, hence internal.
@MainActor
extension XCTestCase {
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
struct WidgetSessionFixture {
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
        userID: "widget-user", givenName: "Alex", familyName: nil
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

    func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
        try XCTUnwrap(credential)
    }
}
