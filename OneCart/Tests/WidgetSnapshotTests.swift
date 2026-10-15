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
    /// REQ-SHELL-030: the app writes the system appearance, so the widget follows the device.
    func test_REQ_SHELL_030_widgetSnapshotFollowsTheDeviceAppearance() throws {
        let store = try makeWidgetStore().store
        let session = try makeTestSession(widgetStore: store)
        session.isReady = true
        session.updateWidgetSnapshot()
        let loaded = try XCTUnwrap(store.loadSnapshot())
        XCTAssertEqual(loaded.themeRaw, "system")
        XCTAssertNil(loaded.preferredColorScheme)
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

        let legacyJson = Data(
            """
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
    }

    func test_REQ_WIDGET_010_legacySnapshotFallsBackToEmeraldWithEmptySuite() throws {
        let suite = try makeDefaults()

        XCTAssertEqual(WidgetCartSnapshot.accentColor(raw: nil, legacyDefaults: suite), .emerald)
        XCTAssertEqual(WidgetCartSnapshot.accentColor(raw: nil, legacyDefaults: nil), .emerald)
        XCTAssertEqual(WidgetCartSnapshot.accentColor(raw: "unknown", legacyDefaults: suite), .emerald)
    }

    func test_REQ_WIDGET_010_legacySnapshotUsesTheStoredAccent() throws {
        let suite = try makeDefaults()
        suite.set("ocean", forKey: "onecart.accent-color")

        XCTAssertEqual(WidgetCartSnapshot.accentColor(raw: nil, legacyDefaults: suite), .ocean)
        XCTAssertEqual(WidgetCartSnapshot.accentColor(raw: "berry", legacyDefaults: suite), .berry)
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
    func test_REQ_WIDGET_020_pendingPurchases_afterStoreRecreation_preservesCommandsUntilIndividualAcknowledgement()
        throws
    {
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
        try reopened.enqueuePurchase(
            WidgetPurchaseRequest(
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
