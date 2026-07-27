import CloudKit
import CoreData
import CoreLocation
@testable import OneCart
import XCTest

final class CatalogPriceTests: XCTestCase {
    func testRefreshCatalogPricesUpdatesMatchingSourceURL() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let (_, listID, productID) = try await seedCart(
            repository: repository,
            draft: ProductDraft(
                name: "Молоко",
                quantity: 1,
                unit: .piece,
                category: .dairy,
                estimatedPrice: 40,
                note: "",
                sourceURL: "https://shop.example.com/milk?utm=1"
            )
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_721_280_000)

        let updated = try await repository.refreshCatalogPrices(
            in: listID,
            snapshots: [
                CatalogPriceSnapshot(
                    sourceURL: "https://shop.example.com/milk",
                    price: 49.9,
                    originalPrice: 69.9,
                    loyaltyPrice: 44.9,
                    fetchedAt: fetchedAt,
                    promotionEndsAt: fetchedAt.addingTimeInterval(86_400)
                ),
            ]
        )

        XCTAssertEqual(updated, 1)
        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(product.estimatedPriceValue, 49.9, accuracy: 0.001)
        XCTAssertEqual(product.originalPrice?.doubleValue ?? 0, 69.9, accuracy: 0.001)
        XCTAssertEqual(product.loyaltyPrice?.doubleValue ?? 0, 44.9, accuracy: 0.001)
        XCTAssertEqual(product.catalogFetchedAt, fetchedAt)
    }

    func testRefreshCatalogPricesIgnoresStaleSnapshot() async throws {
        let (_, repository) = try await makeInMemoryRepository()
        let fetchedAt = Date(timeIntervalSince1970: 1_721_280_000)
        let (_, listID, productID) = try await seedCart(
            repository: repository,
            draft: ProductDraft(
                name: "Молоко",
                quantity: 1,
                unit: .piece,
                category: .dairy,
                estimatedPrice: 40,
                note: "",
                sourceURL: "https://shop.example.com/milk",
                catalogFetchedAt: fetchedAt
            )
        )

        let updated = try await repository.refreshCatalogPrices(
            in: listID,
            snapshots: [
                CatalogPriceSnapshot(
                    sourceURL: "https://shop.example.com/milk",
                    price: 99,
                    originalPrice: nil,
                    loyaltyPrice: nil,
                    fetchedAt: fetchedAt.addingTimeInterval(-60),
                    promotionEndsAt: nil
                ),
            ]
        )

        XCTAssertEqual(updated, 0)
        let product = try XCTUnwrap(fetchProduct(id: productID, repository: repository))
        XCTAssertEqual(product.estimatedPriceValue, 40, accuracy: 0.001)
    }

    func testCatalogPriceSnapshotStripsQueryAndFragment() {
        XCTAssertEqual(
            CatalogPriceSnapshot.canonicalSourceURL(
                from: "https://shop.example.com/item?x=1#frag"
            ),
            "https://shop.example.com/item"
        )
    }

    func testOfficialProductMediaUsesSelectedStoreCatalogOnly() {
        XCTAssertEqual(
            OfficialProductMedia.resolve(
                productName: "Бананы",
                storeName: "АТБ"
            )?.sourceName,
            "АТБ"
        )
        XCTAssertNil(
            OfficialProductMedia.resolve(
                productName: "Молоко",
                storeName: "АТБ"
            )
        )
        XCTAssertEqual(
            OfficialProductMedia.resolve(
                productName: "Молоко",
                storeName: "Сільпо"
            )?.sourceName,
            "Сільпо"
        )
    }
}
