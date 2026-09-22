import AppIntents
import Foundation

/// The Live Activity's stop button (REQ-WIDGET-060). Like the purchase toggle it runs in
/// the app process, where the session owns the trip.
public struct EndShoppingTripIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "intent.end_trip.title"
    public static let description = IntentDescription("intent.end_trip.description")
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        #if ONECART_WIDGET_EXTENSION
            try requireHostProcess()
        #else
            await OneCartAppComposition.session.endShoppingTrip()
        #endif
        return .result()
    }

    #if ONECART_WIDGET_EXTENSION
        private func requireHostProcess() throws {
            throw WidgetPurchaseError.unavailable
        }
    #endif
}
