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

    #if !ONECART_WIDGET_EXTENSION
        /// A Live Activity intent performs in the app process, where `OneCartApp` registered the
        /// session; the extension's copy never reads it.
        @Dependency private var cart: any CartIntentHandling
    #endif

    public func perform() async throws -> some IntentResult {
        // Validated before the dependency is read, so a malformed request never needs the app.
        _ = try makeRequest()
        #if ONECART_WIDGET_EXTENSION
            try requireHostProcess()
        #else
            // One forwarding path, so the tests of perform(using:) cover production.
            try await perform(using: cart)
        #endif
        return .result()
    }

    /// Malformed IDs throw `invalidRequest` before anything reaches the app.
    func makeRequest() throws -> WidgetPurchaseRequest {
        guard let productID = UUID(uuidString: productID),
            let accountID = UUID(uuidString: accountID),
            let familyID = UUID(uuidString: familyID),
            let requestID = UUID(uuidString: requestID)
        else {
            throw WidgetPurchaseError.invalidRequest
        }
        return WidgetPurchaseRequest(
            id: requestID,
            accountID: accountID,
            familyID: familyID,
            productID: productID,
            isPurchased: isPurchased
        )
    }

    #if ONECART_WIDGET_EXTENSION
        private func requireHostProcess() throws {
            throw WidgetPurchaseError.unavailable
        }
    #else
        @MainActor
        func perform(using cart: any CartIntentHandling) async throws {
            try await cart.handleWidgetPurchase(makeRequest())
        }
    #endif
}
