import WidgetKit

extension WidgetSnapshotStore {
    /// The app's App Group store; every write reloads the widget timelines. The widget
    /// extension defines its own `shared` next to its timeline provider.
    static let shared = WidgetSnapshotStore(reloadTimelines: {
        WidgetCenter.shared.reloadAllTimelines()
    })
}
