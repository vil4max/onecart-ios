import AppIntents

/// Siri phrases and Shortcuts tiles (REQ-SIRI-040). Phrases are localized in
/// `AppShortcuts.xcstrings`; every phrase names the app, as App Shortcuts require.
struct OneCartShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddCartItemsIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add an item to \(.applicationName)",
                "Add to my \(.applicationName) cart",
            ],
            shortTitle: "intent.add_item.title",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: RemainingCartItemsIntent(),
            phrases: [
                "What's left in \(.applicationName)",
                "What to buy in \(.applicationName)",
            ],
            shortTitle: "intent.remaining.title",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: StartShoppingTripIntent(),
            phrases: [
                "Start shopping in \(.applicationName)",
                "I'm shopping with \(.applicationName)",
            ],
            shortTitle: "intent.start_trip.title",
            systemImageName: "bag"
        )
    }
}
