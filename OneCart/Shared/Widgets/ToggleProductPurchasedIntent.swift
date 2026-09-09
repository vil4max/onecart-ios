import AppIntents
import Foundation
#if canImport(WidgetKit)
    import WidgetKit
#endif

public struct ToggleProductPurchasedIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Отметить покупку"
    public static var description = IntentDescription("Помечает товар в корзине как купленный или возвращает в список.")

    @Parameter(title: "Product ID")
    public var productID: String

    @Parameter(title: "Account ID")
    public var accountID: String

    @Parameter(title: "Family ID")
    public var familyID: String

    @Parameter(title: "Purchased")
    public var isPurchased: Bool

    @Parameter(title: "Request ID")
    public var requestID: String

    public init() {
        productID = ""
        accountID = ""
        familyID = ""
        isPurchased = false
        requestID = ""
    }

    public init(productID: String, accountID: String, familyID: String, isPurchased: Bool) {
        self.productID = productID
        self.accountID = accountID
        self.familyID = familyID
        self.isPurchased = isPurchased
        requestID = UUID().uuidString
    }

    public func perform() async throws -> some IntentResult {
        guard let productID = UUID(uuidString: productID),
              let accountID = UUID(uuidString: accountID),
              let familyID = UUID(uuidString: familyID),
              let requestID = UUID(uuidString: requestID)
        else {
            throw WidgetPurchaseError.invalidRequest
        }
        #if ONECART_WIDGET_EXTENSION
            try requireHostProcess()
        #else
            let request = WidgetPurchaseRequest(
                id: requestID,
                accountID: accountID,
                familyID: familyID,
                productID: productID,
                isPurchased: isPurchased
            )
            try await OneCartAppComposition.session.performWidgetPurchase(request)
        #endif
        return .result()
    }

    #if ONECART_WIDGET_EXTENSION
        private func requireHostProcess() throws {
            throw WidgetPurchaseError.unavailable
        }
    #endif
}
