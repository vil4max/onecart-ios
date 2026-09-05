@testable import OneCart
import XCTest

final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotEncodingAndDecoding() throws {
        let item1 = WidgetItemSnapshot(
            id: UUID(),
            name: "Молоко 3.2%",
            isPurchased: false,
            categoryRaw: ProductCategory.dairyEggs.rawValue,
            subtitle: "добавил(а) Алекс"
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
            activePartnerName: "Алекс в магазине",
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
        XCTAssertEqual(decoded.activePartnerName, "Алекс в магазине")
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

    func testOptimisticToggleAndPendingQueue() {
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

        let pending = store.drainPendingToggles()
        XCTAssertEqual(pending, [testID])

        let pendingSecondDrain = store.drainPendingToggles()
        XCTAssertTrue(pendingSecondDrain.isEmpty)
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
    func testUpdateWidgetSnapshotThemeOverride() {
        let session = AppSession()
        session.isReady = true
        session.preferences.theme = .light
        session.updateWidgetSnapshot(themeOverride: .dark)
        let loaded = WidgetSnapshotStore.shared.loadSnapshot()
        XCTAssertEqual(loaded?.themeRaw, "dark")
        XCTAssertEqual(loaded?.preferredColorScheme, .dark)
    }
}
