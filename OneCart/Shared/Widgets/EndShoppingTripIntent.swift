import AppIntents
import Foundation

/// The Live Activity's stop button (REQ-WIDGET-060). Like the purchase toggle it runs in
/// the app process, where the session owns the trip.
public struct EndShoppingTripIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "intent.end_trip.title"
    public static let description = IntentDescription("intent.end_trip.description")
    public static let isDiscoverable = false

    #if !ONECART_WIDGET_EXTENSION
        /// Registered by `OneCartApp` in the app process, where this intent performs.
        @Dependency private var cart: any CartIntentHandling
    #endif

    public init() {}

    public func perform() async throws -> some IntentResult {
        #if ONECART_WIDGET_EXTENSION
            try requireHostProcess()
        #else
            await perform(using: cart)
        #endif
        return .result()
    }

    #if ONECART_WIDGET_EXTENSION
        private func requireHostProcess() throws {
            throw WidgetPurchaseError.unavailable
        }
    #else
        @MainActor
        func perform(using cart: any CartIntentHandling) async {
            await cart.handleEndShoppingTrip()
        }
    #endif
}
