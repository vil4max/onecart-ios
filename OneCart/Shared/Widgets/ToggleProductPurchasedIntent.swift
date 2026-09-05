import AppIntents
import Foundation
#if canImport(WidgetKit)
    import WidgetKit
#endif

public struct ToggleProductPurchasedIntent: AppIntent {
    public static var title: LocalizedStringResource = "Отметить покупку"
    public static var description = IntentDescription("Помечает товар в корзине как купленный или возвращает в список.")

    @Parameter(title: "Product ID")
    public var productID: String

    public init() {
        productID = ""
    }

    public init(productID: String) {
        self.productID = productID
    }

    public func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: productID) else {
            return .result()
        }

        WidgetSnapshotStore.shared.toggleItem(id: uuid)
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
        #endif

        return .result()
    }
}
