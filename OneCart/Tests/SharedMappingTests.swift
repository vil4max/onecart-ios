import Foundation
@testable import OneCart
import Testing

/// The mappings the cart screen, the widgets and the shopping trip share instead of each
/// spelling them out.
@Suite("Shared app and widget mappings")
struct SharedMappingTests {
    private static let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")
    private static let familyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")
    private static let productID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")

    private func snapshot(accountID: UUID?, familyID: UUID?) -> WidgetCartSnapshot {
        WidgetCartSnapshot(
            cartTitle: "Weekend",
            totalCount: 1,
            purchasedCount: 0,
            isSyncing: false,
            lastUpdated: Date(timeIntervalSince1970: 0),
            familyMemberCount: 1,
            accountID: accountID,
            familyID: familyID,
            items: []
        )
    }

    @Test("REQ-WIDGET-010: a line's state draws the same check and progress symbols on every surface")
    func symbolNames() {
        #expect(CartSymbolName.purchase(isPurchased: true) == "checkmark.circle.fill")
        #expect(CartSymbolName.purchase(isPurchased: false) == "circle")
        #expect(CartSymbolName.progress(isAllPurchased: true) == "checkmark.seal.fill")
        #expect(CartSymbolName.progress(isAllPurchased: false) == "cart")
    }

    @Test("REQ-WIDGET-020: a widget line's check flips that line in the snapshot's account and cart")
    func widgetToggleIntentFlipsTheLine() throws {
        let productID = try #require(Self.productID)
        let cart = snapshot(accountID: Self.accountID, familyID: Self.familyID)
        for isPurchased in [false, true] {
            let item = WidgetItemSnapshot(id: productID, name: "Milk", isPurchased: isPurchased, categoryRaw: "other")
            let request = try ToggleProductPurchasedIntent(togglingItem: item, in: cart).makeRequest()
            #expect(request.productID == productID)
            #expect(request.accountID == Self.accountID)
            #expect(request.familyID == Self.familyID)
            #expect(request.isPurchased == !isPurchased)
        }
    }

    @Test("REQ-WIDGET-020: a widget check without an account or cart is rejected before the app")
    func widgetToggleIntentWithoutIdentityIsRejected() throws {
        let productID = try #require(Self.productID)
        let item = WidgetItemSnapshot(id: productID, name: "Milk", isPurchased: false, categoryRaw: "other")
        let intent = ToggleProductPurchasedIntent(togglingItem: item, in: snapshot(accountID: nil, familyID: nil))
        #expect(throws: WidgetPurchaseError.self) {
            try intent.makeRequest()
        }
    }

    @Test("REQ-WIDGET-040: a trip line's check marks that line purchased in the trip's account and cart")
    func tripToggleIntentMarksTheLinePurchased() throws {
        let attributes = try ShoppingTripAttributes(
            accountID: #require(Self.accountID),
            familyID: #require(Self.familyID)
        )
        let item = try ShoppingTripItem(id: #require(Self.productID), name: "Bread", categoryRaw: "bakery")
        let request = try ToggleProductPurchasedIntent(purchasingTripItem: item, of: attributes).makeRequest()
        #expect(request.productID == item.id)
        #expect(request.accountID == attributes.accountID)
        #expect(request.familyID == attributes.familyID)
        #expect(request.isPurchased)
    }

    @Test("REQ-SHELL-060: a widget with no cart is titled with the app name from the catalog")
    func emptyWidgetIsTitledWithTheAppName() {
        #expect(WidgetCartSnapshot.empty.cartTitle == String(localized: "common.app_name"))
        #expect(WidgetCartSnapshot.empty.cartTitle == "OneCart Family")
    }
}
