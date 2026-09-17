import Foundation
@testable import OneCart
import XCTest

final class CartActivityDiffTests: XCTestCase {
    private let myName = "Alex"
    private let partnerName = "Maria"

    func testFirstSnapshotSeedsWithoutNotify() {
        let item1 = CartItemSnapshot(
            id: UUID(),
            name: "Хлеб",
            isPurchased: false,
            createdByName: partnerName
        )
        let item2 = CartItemSnapshot(
            id: UUID(),
            name: "Молоко",
            isPurchased: true,
            createdByName: myName
        )

        let diff = CartActivityDiff.evaluate(
            previous: [],
            stored: [],
            current: [item1, item2],
            currentUserName: myName,
            isSharedCart: true
        )

        XCTAssertFalse(diff.shouldNotify)
        XCTAssertTrue(diff.events.isEmpty)
        XCTAssertEqual(diff.nextSnapshot.count, 2)
    }

    func testSingleUserCartDoesNotNotify() {
        let item = CartItemSnapshot(
            id: UUID(),
            name: "Яблоки",
            isPurchased: false,
            createdByName: partnerName
        )

        let diff = CartActivityDiff.evaluate(
            previous: [],
            stored: [item],
            current: [
                item,
                CartItemSnapshot(id: UUID(), name: "Груши", isPurchased: false, createdByName: partnerName),
            ],
            currentUserName: myName,
            isSharedCart: false
        )

        XCTAssertFalse(diff.shouldNotify)
        XCTAssertTrue(diff.events.isEmpty)
    }

    func testPartnerAddsSingleItemNotifies() {
        let existing = CartItemSnapshot(
            id: UUID(),
            name: "Хлеб",
            isPurchased: false,
            createdByName: myName
        )
        let added = CartItemSnapshot(
            id: UUID(),
            name: "Сыр",
            isPurchased: false,
            createdByName: partnerName
        )

        let diff = CartActivityDiff.evaluate(
            previous: [existing],
            stored: [existing],
            current: [existing, added],
            currentUserName: myName,
            isSharedCart: true
        )

        XCTAssertTrue(diff.shouldNotify)
        XCTAssertEqual(diff.events.count, 1)
        guard case let .itemsAdded(author, names) = diff.events.first else {
            XCTFail("Expected itemsAdded event")
            return
        }
        XCTAssertEqual(author, partnerName)
        XCTAssertEqual(names, ["Сыр"])
    }

    func testPartnerAddsMultipleItemsAggregates() {
        let existing = CartItemSnapshot(
            id: UUID(),
            name: "Хлеб",
            isPurchased: false,
            createdByName: myName
        )
        let item1 = CartItemSnapshot(
            id: UUID(),
            name: "Сыр",
            isPurchased: false,
            createdByName: partnerName
        )
        let item2 = CartItemSnapshot(
            id: UUID(),
            name: "Масло",
            isPurchased: false,
            createdByName: partnerName
        )

        let diff = CartActivityDiff.evaluate(
            previous: [existing],
            stored: [existing],
            current: [existing, item1, item2],
            currentUserName: myName,
            isSharedCart: true
        )

        XCTAssertTrue(diff.shouldNotify)
        XCTAssertEqual(diff.events.count, 1)
        guard case let .itemsAdded(author, names) = diff.events.first else {
            XCTFail("Expected itemsAdded event")
            return
        }
        XCTAssertEqual(author, partnerName)
        XCTAssertEqual(names, ["Сыр", "Масло"])
    }

    func testSelfAddedItemDoesNotNotify() {
        let existing = CartItemSnapshot(
            id: UUID(),
            name: "Хлеб",
            isPurchased: false,
            createdByName: partnerName
        )
        let selfAdded = CartItemSnapshot(
            id: UUID(),
            name: "Кофе",
            isPurchased: false,
            createdByName: myName
        )

        let diff = CartActivityDiff.evaluate(
            previous: [existing],
            stored: [existing],
            current: [existing, selfAdded],
            currentUserName: myName,
            isSharedCart: true
        )

        XCTAssertFalse(diff.shouldNotify)
        XCTAssertTrue(diff.events.isEmpty)
    }

    func testPartnerCompletesLastItemNotifiesAllPurchased() {
        let id1 = UUID()
        let id2 = UUID()

        let baseline = [
            CartItemSnapshot(id: id1, name: "Хлеб", isPurchased: true, createdByName: myName, purchasedByName: myName),
            CartItemSnapshot(id: id2, name: "Молоко", isPurchased: false, createdByName: myName),
        ]

        let updated = [
            CartItemSnapshot(id: id1, name: "Хлеб", isPurchased: true, createdByName: myName, purchasedByName: myName),
            CartItemSnapshot(
                id: id2,
                name: "Молоко",
                isPurchased: true,
                createdByName: myName,
                purchasedByName: partnerName
            ),
        ]

        let diff = CartActivityDiff.evaluate(
            previous: baseline,
            stored: baseline,
            current: updated,
            currentUserName: myName,
            isSharedCart: true
        )

        XCTAssertTrue(diff.shouldNotify)
        XCTAssertEqual(diff.events.count, 1)
        guard case let .allPurchased(author) = diff.events.first else {
            XCTFail("Expected allPurchased event")
            return
        }
        XCTAssertEqual(author, partnerName)
    }

    func testSelfCompletesLastItemDoesNotNotify() {
        let id1 = UUID()
        let id2 = UUID()

        let baseline = [
            CartItemSnapshot(
                id: id1,
                name: "Хлеб",
                isPurchased: true,
                createdByName: partnerName,
                purchasedByName: partnerName
            ),
            CartItemSnapshot(id: id2, name: "Молоко", isPurchased: false, createdByName: partnerName),
        ]

        let updated = [
            CartItemSnapshot(
                id: id1,
                name: "Хлеб",
                isPurchased: true,
                createdByName: partnerName,
                purchasedByName: partnerName
            ),
            CartItemSnapshot(
                id: id2,
                name: "Молоко",
                isPurchased: true,
                createdByName: partnerName,
                purchasedByName: myName
            ),
        ]

        let diff = CartActivityDiff.evaluate(
            previous: baseline,
            stored: baseline,
            current: updated,
            currentUserName: myName,
            isSharedCart: true
        )

        XCTAssertFalse(diff.shouldNotify)
        XCTAssertTrue(diff.events.isEmpty)
    }

    func testPartialCompletionDoesNotNotifyAllPurchased() {
        let id1 = UUID()
        let id2 = UUID()

        let baseline = [
            CartItemSnapshot(id: id1, name: "Хлеб", isPurchased: false, createdByName: myName),
            CartItemSnapshot(id: id2, name: "Молоко", isPurchased: false, createdByName: myName),
        ]

        let updated = [
            CartItemSnapshot(
                id: id1,
                name: "Хлеб",
                isPurchased: true,
                createdByName: myName,
                purchasedByName: partnerName
            ),
            CartItemSnapshot(id: id2, name: "Молоко", isPurchased: false, createdByName: myName),
        ]

        let diff = CartActivityDiff.evaluate(
            previous: baseline,
            stored: baseline,
            current: updated,
            currentUserName: myName,
            isSharedCart: true
        )

        XCTAssertFalse(diff.shouldNotify)
        XCTAssertTrue(diff.events.isEmpty)
    }
}
