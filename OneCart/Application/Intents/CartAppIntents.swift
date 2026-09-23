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
        return .result(dialog: IntentDialog(CartIntentSpeech.addResult(result)))
    }
}

/// «Что осталось в OneCart»: reads the lines still to buy (REQ-SIRI-020).
struct RemainingCartItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.remaining.title"
    static let description = IntentDescription("intent.remaining.description")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let remaining = try await OneCartAppComposition.session.remainingItemsForIntent()
        return .result(dialog: IntentDialog(CartIntentSpeech.remaining(remaining)))
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

/// What Siri says back; kept apart from the intents so tests check the exact sentences. Every
/// sentence stays a `LocalizedStringResource`: App Intents resolves it late, in the language of
/// the request, where `String(localized:)` would fix the app's own language at once.
enum CartIntentSpeech {
    /// Siri reads a short list; the rest is summarized as "N more".
    static let spokenNameLimit = 5

    static func addResult(_ result: CartIntentAddResult) -> LocalizedStringResource {
        var sentences: [LocalizedStringResource] = []
        if !result.added.isEmpty {
            sentences.append("intent.add_item.added \(result.added, format: .list(type: .and))")
        }
        if !result.alreadyOnCart.isEmpty {
            sentences.append("intent.add_item.already \(result.alreadyOnCart, format: .list(type: .and))")
        }
        if !result.failed.isEmpty {
            sentences.append("intent.add_item.failed \(result.failed, format: .list(type: .and))")
        }
        return joined(sentences) ?? CartIntentError.failed.localizedStringResource
    }

    static func remaining(_ remaining: CartIntentRemaining) -> LocalizedStringResource {
        if remaining.totalCount == 0 {
            return "widget.empty"
        }
        if remaining.names.isEmpty {
            return "widget.all_purchased"
        }
        let spoken = Array(remaining.names.prefix(spokenNameLimit))
        let list: LocalizedStringResource =
            "intent.remaining.list \(remaining.names.count) \(spoken, format: .list(type: .and))"
        let unspoken = remaining.names.count - spoken.count
        guard unspoken > 0 else { return list }
        return joined([list, "intent.remaining.more \(unspoken)"]) ?? list
    }

    /// One dialog of several sentences; each part is still resolved in the request's language.
    private static func joined(_ sentences: [LocalizedStringResource]) -> LocalizedStringResource? {
        guard let first = sentences.first else { return nil }
        return sentences.dropFirst().reduce(first) { "intent.sentences \($0) \($1)" }
    }
}
