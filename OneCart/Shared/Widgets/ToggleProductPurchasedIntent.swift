import AppIntents
import Foundation

public struct ToggleProductPurchasedIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "intent.toggle_purchased.title"
    public static let description = IntentDescription("intent.toggle_purchased.description")
    /// Only the widget and the Live Activity build this intent; it is not a Shortcuts action.
    public static let isDiscoverable = false

    @Parameter(title: "intent.toggle_purchased.product_id")
    public var productID: String

    @Parameter(title: "intent.toggle_purchased.account_id")
    public var accountID: String

    @Parameter(title: "intent.toggle_purchased.family_id")
    public var familyID: String

    @Parameter(title: "intent.toggle_purchased.is_purchased")
    public var isPurchased: Bool

    @Parameter(title: "intent.toggle_purchased.request_id")
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
