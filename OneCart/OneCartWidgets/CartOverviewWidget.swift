import SwiftUI
import WidgetKit

struct CartWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetCartSnapshot
}

struct CartWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> CartWidgetEntry {
        CartWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CartWidgetEntry) -> Void) {
        if context.isPreview {
            completion(CartWidgetEntry(date: Date(), snapshot: .placeholder))
            return
        }
        let snapshot = WidgetSnapshotStore.shared.loadSnapshot() ?? .empty
        completion(CartWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<CartWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.shared.loadSnapshot() ?? .empty
        let entry = CartWidgetEntry(date: Date(), snapshot: snapshot)
        // Only the app and the toggle intent write the snapshot, and both reload the
        // timelines, so a periodic refresh would re-read unchanged data.
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct CartWidgetContainerView: View {
    @Environment(\.colorScheme) private var systemScheme
    let entry: CartWidgetEntry

    private var activeScheme: ColorScheme {
        entry.snapshot.preferredColorScheme ?? systemScheme
    }

    var body: some View {
        CartWidgetRootView(entry: entry)
            .environment(\.colorScheme, activeScheme)
            .preferredColorScheme(activeScheme)
            .containerBackground(OneCartPalette.widgetBackground(for: activeScheme), for: .widget)
    }
}

struct CartOverviewWidget: Widget {
    let kind: String = "OneCartOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CartWidgetProvider()) { entry in
            CartWidgetContainerView(entry: entry)
        }
        .configurationDisplayName("widget.display_name")
        .description("widget.description")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium,
            .systemLarge,
        ])
        .contentMarginsDisabled()
    }
}
