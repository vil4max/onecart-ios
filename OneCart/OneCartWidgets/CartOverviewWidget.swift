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
        let snapshot = WidgetSnapshotStore.shared.loadSnapshot() ?? .placeholder
        completion(CartWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<CartWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.shared.loadSnapshot() ?? .placeholder
        let entry = CartWidgetEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
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
        .configurationDisplayName("Корзина OneCart")
        .description("Быстрый доступ к семейной корзине и вычеркивание покупок на ходу.")
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
