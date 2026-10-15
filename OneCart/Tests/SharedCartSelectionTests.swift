import CoreData
@testable import OneCart
import XCTest

@MainActor
final class SharedCartSelectionTests: XCTestCase, SharedCartSeeding {
    func test_REQ_SYNC_040_cloudReloadKeepsChosenSharedCartWhenAnotherSharedCartIsNewer() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let chosenID = try await seedSharedCart(
            persistence: persistence,
            name: "Выбранная",
            productName: "Chosen",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        let otherID = try await seedSharedCart(
            persistence: persistence,
            name: "Другая",
            productName: "Other",
            updatedAt: Date()
        )
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()
        let chosen = try XCTUnwrap(session.familySpaces.first { $0.id == chosenID })
        session.setActiveFamilySpace(chosen)
        XCTAssertEqual(session.activeFamilySpace?.id, chosenID)

        // Every cloud import runs the same join offer; the other cart stays the most recently edited.
        try await session.offerSharedCartJoinIfNeededForTesting()
        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, chosenID)
        XCTAssertEqual(
            defaults.string(forKey: activeFamilyKey(accountID: account.id)),
            chosenID.uuidString
        )
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Chosen"])
        XCTAssertEqual(Set(session.familySpaces.compactMap(\.id)), [chosenID, otherID])
    }

    func test_REQ_SHARE_090_newlyJoinedSharedCartBecomesActiveOverCurrentSharedCart() async throws {
        let persistence = PersistenceController(inMemory: true, cloudKitEnabled: false)
        try await persistence.load()
        let defaults = try makeDefaults()
        let account = OneCartAccount(id: UUID(), displayName: "Саша")
        let currentID = try await seedSharedCart(
            persistence: persistence,
            name: "Текущая",
            productName: "Current",
            updatedAt: Date()
        )
        let session = try makeTestSession(
            persistence: persistence,
            defaults: defaults
        )
        try session.bootstrapTestingSession(account: account)
        try await session.offerSharedCartJoinIfNeededForTesting()
        XCTAssertEqual(session.activeFamilySpace?.id, currentID)

        // Older updatedAt proves selection follows the join, not the sort order.
        let joinedID = try await seedSharedCart(
            persistence: persistence,
            name: "Новая",
            productName: "Joined",
            updatedAt: Date().addingTimeInterval(-3600)
        )
        try await session.offerSharedCartJoinIfNeededForTesting()

        XCTAssertEqual(session.activeFamilySpace?.id, joinedID)
        XCTAssertEqual(Set(session.products.map(\.displayName)), ["Joined"])
    }
}

/// Shared by the join and selection suites. A protocol rather than an `XCTestCase` extension,
/// because another suite declares its own private `activeFamilyKey(accountID:)`.
@MainActor
protocol SharedCartSeeding {}

extension SharedCartSeeding {
    func seedSharedCart(
        persistence: PersistenceController,
        name: String,
        productName: String?,
        includeList: Bool = true,
        updatedAt: Date = Date()
    ) async throws -> UUID {
        let sharedID = UUID()
        let listID = UUID()
        try await persistence.performBackgroundTask { context in
            let space = FamilySpace(context: context)
            try persistence.assign(space, to: .shared, in: context)
            space.id = sharedID
            space.name = name
            space.createdAt = updatedAt
            space.updatedAt = updatedAt
            space.isHouseholdDefault = NSNumber(value: true)

            guard includeList else { return }

            let list = ShoppingListEntity(context: context)
            try persistence.assign(list, toSameStoreAs: space, in: context)
            list.id = listID
            list.title = String(localized: "common.default_list")
            list.status = ShoppingListStatus.active.rawValue
            list.createdAt = updatedAt
            list.updatedAt = updatedAt
            list.familySpace = space

            if let productName {
                let product = ProductEntity(context: context)
                try persistence.assign(product, toSameStoreAs: space, in: context)
                product.id = UUID()
                product.name = productName
                product.quantity = NSNumber(value: 1)
                product.unit = ProductUnit.piece.rawValue
                product.category = ProductCategory.other.rawValue
                product.estimatedPrice = NSNumber(value: 0)
                product.isPurchased = NSNumber(value: false)
                product.createdAt = updatedAt
                product.updatedAt = updatedAt
                product.familySpace = space
                product.list = list
            }
        }
        persistence.container.viewContext.processPendingChanges()
        return sharedID
    }

    func activeFamilyKey(accountID: UUID) -> String {
        "onecart.active-family-space-id.\(accountID.uuidString)"
    }
}
