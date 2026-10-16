import CoreData
@testable import OneCart
import XCTest

/// A queued widget purchase compares the purchase version, not `updatedAt`, which every edit
/// moves (REQ-WIDGET-020).
@MainActor
extension WidgetSnapshotTests {
    func test_REQ_WIDGET_020_purchaseQueuedBeforeARenameIsAppliedAndTheRenameMovesUpdatedAt() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request(createdAt: Date())
        try fixture.store.enqueuePurchase(request)
        try await fixture.repository.updateProduct(
            id: fixture.productID, familySpaceID: fixture.familyID, draft: productDraft(name: "Oat milk")
        )
        let renamed = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.repository))
        XCTAssertGreaterThan(try XCTUnwrap(renamed.updatedAt), request.createdAt)

        try await fixture.session.performWidgetPurchase(request)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.displayName, "Oat milk")
        XCTAssertEqual(product.purchaseUpdatedAt, request.createdAt)
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    func test_REQ_WIDGET_020_purchaseQueuedBeforeANewerAppPurchaseChangeIsIgnored() async throws {
        let fixture = try await makeWidgetSession()
        let request = fixture.request(isPurchased: false, createdAt: Date().addingTimeInterval(-60))
        try fixture.store.enqueuePurchase(request)
        try await fixture.repository.setPurchasedState(
            id: fixture.productID, familySpaceID: fixture.familyID, isPurchased: true,
            participantDisplayName: "Alex"
        )

        try await fixture.session.performWidgetPurchase(request)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.purchasedByName, "Alex")
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    /// A row written before V9 has no purchase version; its `updatedAt` stands in for one, and a
    /// rename keeps that old value as the version before it moves `updatedAt`.
    func test_REQ_WIDGET_020_rowWithoutAPurchaseVersionFallsBackToUpdatedAt() async throws {
        let fixture = try await makeWidgetSession()
        let legacyUpdatedAt = Date().addingTimeInterval(-60)
        try await makeLegacyRow(fixture, updatedAt: legacyUpdatedAt)
        let stale = fixture.request(createdAt: legacyUpdatedAt.addingTimeInterval(-1))
        let queued = fixture.request(createdAt: legacyUpdatedAt.addingTimeInterval(1))
        try fixture.store.enqueuePurchase(stale)
        try await fixture.session.performWidgetPurchase(stale)
        let afterStale = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.repository))
        XCTAssertFalse(afterStale.isPurchasedValue)

        try fixture.store.enqueuePurchase(queued)
        try await fixture.repository.updateProduct(
            id: fixture.productID, familySpaceID: fixture.familyID, draft: productDraft(name: "Oat milk")
        )
        try await fixture.session.performWidgetPurchase(queued)

        let product = try XCTUnwrap(fetchProduct(id: fixture.productID, repository: fixture.repository))
        XCTAssertTrue(product.isPurchasedValue)
        XCTAssertEqual(product.displayName, "Oat milk")
        XCTAssertTrue(try fixture.store.pendingPurchases().isEmpty)
    }

    /// Clears the purchase version, as on a row an older client wrote.
    private func makeLegacyRow(_ fixture: WidgetSessionFixture, updatedAt: Date) async throws {
        let productID = fixture.productID
        let persistence = fixture.session.persistence
        try await persistence.performBackgroundTask { context in
            guard let product = try RepositoryFetch.product(id: productID, in: context) else {
                throw RepositoryError.productNotFound
            }
            product.purchaseUpdatedAt = nil
            product.updatedAt = updatedAt
        }
        persistence.container.viewContext.processPendingChanges()
    }
}
