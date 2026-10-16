import Foundation

/// What the Siri, widget and Live Activity intents ask of the app. `OneCartApp` registers the
/// session's `CartIntentHandler` under this type with `AppDependencyManager` at launch; each intent reads it through
/// `@Dependency` and forwards to `perform(using:)`, which tests call with a fake.
@MainActor
protocol CartIntentHandling: AnyObject, Sendable {
    func handleAddItems(_ raw: String) async throws -> CartIntentAddResult
    func handleRemainingItems() async throws -> CartIntentRemaining
    func handleStartShoppingTrip() async throws
    func handleWidgetPurchase(_ request: WidgetPurchaseRequest) async throws
    func handleEndShoppingTrip() async
}
