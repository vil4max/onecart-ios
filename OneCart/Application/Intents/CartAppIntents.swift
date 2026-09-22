import AppIntents
import Foundation

/// «Добавь в OneCart»: Siri asks for the names and adds name-only lines (REQ-SIRI-010).
struct AddCartItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.add_item.title"
    static let description = IntentDescription("intent.add_item.description")

    @Parameter(title: "intent.add_item.name", requestValueDialog: IntentDialog("intent.add_item.prompt"))
    var names: String

    init() {}

    init(names: String) {
        self.names = names
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await OneCartAppComposition.session.addItemsFromIntent(names)
        return .result(dialog: "\(CartIntentSpeech.addResult(result))")
    }
}

/// «Что осталось в OneCart»: reads the lines still to buy (REQ-SIRI-020).
struct RemainingCartItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.remaining.title"
    static let description = IntentDescription("intent.remaining.description")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let remaining = try await OneCartAppComposition.session.remainingItemsForIntent()
        return .result(dialog: "\(CartIntentSpeech.remaining(remaining))")
    }
}

/// «Я в магазине» by voice: starts the shopping trip Live Activity (REQ-SIRI-030). A Live
/// Activity intent may start an activity while the app stays in the background.
struct StartShoppingTripIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "intent.start_trip.title"
    static let description = IntentDescription("intent.start_trip.description")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await OneCartAppComposition.session.startShoppingTripFromIntent()
        return .result(dialog: "intent.start_trip.started")
    }
}

/// What Siri says back; kept apart from the intents so tests check the exact sentences.
enum CartIntentSpeech {
    /// Siri reads a short list; the rest is summarized as "N more".
    static let spokenNameLimit = 5

    static func addResult(_ result: CartIntentAddResult) -> String {
        var sentences: [String] = []
        if !result.added.isEmpty {
            sentences.append(String(localized: "intent.add_item.added \(list(result.added))"))
        }
        if !result.alreadyOnCart.isEmpty {
            sentences.append(String(localized: "intent.add_item.already \(list(result.alreadyOnCart))"))
        }
        return sentences.joined(separator: " ")
    }

    static func remaining(_ remaining: CartIntentRemaining) -> String {
        if remaining.totalCount == 0 {
            return String(localized: "widget.empty")
        }
        if remaining.names.isEmpty {
            return String(localized: "widget.all_purchased")
        }
        let spoken = Array(remaining.names.prefix(spokenNameLimit))
        var sentence = String(localized: "intent.remaining.list \(remaining.names.count) \(list(spoken))")
        let unspoken = remaining.names.count - spoken.count
        if unspoken > 0 {
            sentence += " " + String(localized: "trip.more \(unspoken)")
        }
        return sentence
    }

    private static func list(_ names: [String]) -> String {
        names.formatted(.list(type: .and))
    }
}
