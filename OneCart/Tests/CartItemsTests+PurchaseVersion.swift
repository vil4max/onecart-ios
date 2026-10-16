import CoreData
@testable import OneCart
import XCTest

/// Widget purchase commands against the purchase version, on a test clock (REQ-WIDGET-020).
extension CartItemsTests {
    /// A command the row already matches is no edit: `updatedAt` stays, so a later edit still
    /// wins last-writer-wins (REQ-SYNC-040), and only the purchase version advances, so an older
    /// command replayed after it is still ignored.
    func test_REQ_WIDGET_020_commandMatchingTheRowKeepsUpdatedAtAndOrdersReplay() async throws {
        let clock = TestClock()
        let (_, repository) = try await makeInMemoryRepository(clock: clock.appClock)
        let (familyID, _, productID) = try await seedCart(repository: repository)
        try await repository.setPurchasedState(
            id: productID, familySpaceID: familyID, isPurchased: true, participantDisplayName: "Alex"
        )
        let checkedAt = clock.now()
        clock.advance(by: .seconds(60))
        let staleUncheckAt = clock.now()
        clock.advance(by: .seconds(60))
        let matchingCheckAt = clock.now()
        clock.advance(by: .seconds(60))

        try await repository.setPurchased(
            id: productID, familySpaceID: familyID, isPurchased: true,
            participantDisplayName: "Sam", purchasedAt: matchingCheckAt
        )
        try await repository.setPurchased(
            id: productID, familySpaceID: familyID, isPurchased: false,
            participantDisplayName: "Sam", purchasedAt: staleUncheckAt
        )

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedByName, "Alex")
        XCTAssertEqual(product.updatedAt, checkedAt)
        XCTAssertEqual(product.purchaseUpdatedAt, matchingCheckAt)
    }

    /// A pre-V9 row may have no `updatedAt`; a rename then keeps its creation time as the purchase
    /// version, so a widget tap queued before the rename still applies.
    func test_REQ_WIDGET_020_renameOfARowWithoutDatesKeepsAnEarlierQueuedPurchase() async throws {
        let clock = TestClock()
        let (persistence, repository) = try await makeInMemoryRepository(clock: clock.appClock)
        let (familyID, _, productID) = try await seedCart(repository: repository)
        try await editRow(productID, in: persistence) { product in
            product.purchaseUpdatedAt = nil
            product.updatedAt = nil
        }
        clock.advance(by: .seconds(60))
        let queuedAt = clock.now()
        clock.advance(by: .seconds(60))

        try await repository.updateProduct(
            id: productID, familySpaceID: familyID, draft: productDraft(name: "Oat milk")
        )
        try await repository.setPurchased(
            id: productID, familySpaceID: familyID, isPurchased: true,
            participantDisplayName: "Sam", purchasedAt: queuedAt
        )

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.displayName, "Oat milk")
        XCTAssertEqual(product.purchaseUpdatedAt, queuedAt)
    }

    /// A pre-V9 build checks a line without stamping `purchaseUpdatedAt`; its `purchasedAt` still
    /// makes a widget uncheck queued before that check too old to replace it.
    func test_REQ_WIDGET_020_olderWidgetUncheckKeepsALaterCheckFromAPreV9Build() async throws {
        let clock = TestClock()
        let (persistence, repository) = try await makeInMemoryRepository(clock: clock.appClock)
        let (familyID, _, productID) = try await seedCart(repository: repository)
        let staleVersion = clock.now()
        clock.advance(by: .seconds(60))
        let queuedUncheckAt = clock.now()
        clock.advance(by: .seconds(60))
        let partnerCheckAt = clock.now()
        try await editRow(productID, in: persistence) { product in
            product.isPurchased = NSNumber(value: true)
            product.purchasedAt = partnerCheckAt
            product.purchasedByName = "Sam"
            product.updatedAt = partnerCheckAt
        }

        try await repository.setPurchased(
            id: productID, familySpaceID: familyID, isPurchased: false,
            participantDisplayName: "Alex", purchasedAt: queuedUncheckAt
        )

        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedByName, "Sam")
        XCTAssertEqual(product.purchaseUpdatedAt, staleVersion)
    }

    /// Writes a row the way another client left it, bypassing the repository.
    private func editRow(
        _ productID: UUID,
        in persistence: PersistenceController,
        _ change: @escaping @Sendable (ProductEntity) -> Void
    ) async throws {
        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: productID, in: context) else {
                throw RepositoryError.productNotFound
            }
            change(product)
        }
        persistence.container.viewContext.processPendingChanges()
    }
}
