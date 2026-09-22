import SwiftUI

struct HistoryView: View {
    let viewModel: HistoryViewModel

    /// The pushed value is the snapshot the row was tapped with; the detail resolves its live
    /// contents through the ViewModel.
    @State private var path: [HistoryDayGroup] = []
    #if DEBUG
        @State private var hasOpenedDemoDetail = false
    #endif

    var body: some View {
        // Grouping dedupes and sorts the whole history; evaluate it once per body pass.
        let groups = viewModel.dayGroups
        NavigationStack(path: $path) {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("history.empty_headline", systemImage: "clock")
                    } description: {
                        Text("history.empty_message")
                    }
                } else {
                    dayList(groups)
                }
            }
            .navigationTitle("history.nav_title")
            .navigationDestination(for: HistoryDayGroup.self) { group in
                HistoryDayDetailView(viewModel: viewModel, group: group)
            }
        }
        #if DEBUG
        .onChange(of: groups.first?.id, initial: true) {
                openDemoDetailIfRequested(groups)
            }
        #endif
    }

    /// Read-only by requirement (REQ-SHELL-020): rows carry no swipe actions and no delete.
    private func dayList(_ groups: [HistoryDayGroup]) -> some View {
        List {
            Section {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        HistoryDayRow(group: group)
                    }
                }

                if viewModel.hasMore {
                    Button("history.show_more") {
                        viewModel.loadMore()
                    }
                }
            } footer: {
                Text("history.how_it_works")
            }
        }
        .listStyle(.insetGrouped)
    }

    #if DEBUG
        /// Demo launches (`-oneCartDemoHistoryDetail`) open the newest day for screenshots.
        private func openDemoDetailIfRequested(_ groups: [HistoryDayGroup]) {
            guard !hasOpenedDemoDetail,
                  ProcessInfo.processInfo.arguments.contains("-oneCartDemoHistoryDetail"),
                  let newest = groups.first
            else { return }
            hasOpenedDemoDetail = true
            path = [newest]
        }
    #endif
}

struct HistoryDayGroup: Identifiable, Hashable {
    let dayStart: Date
    let items: [HistoryItemEntity]

    var id: Date {
        dayStart
    }

    func title(locale: Locale? = nil) -> String {
        HistoryDayFormatting.title(for: dayStart, locale: locale)
    }

    /// The day's items in the cart's category order, so both tabs section alike.
    var categorySections: [(category: ProductCategory, items: [HistoryItemEntity])] {
        ProductCategory.groupedSections(from: items) { $0.categoryValue }
    }

    var namesPreview: String {
        items.map(\.displayName).joined(separator: ", ")
    }

    static func groups(
        from entries: [PurchaseHistoryEntity],
        calendar: Calendar = .current
    ) -> [HistoryDayGroup] {
        let items = HistoryItems.unique(from: entries)
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.purchaseMoment)
        }
        return grouped
            .map { dayStart, dayItems in
                HistoryDayGroup(
                    dayStart: dayStart,
                    items: dayItems.sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                            == .orderedAscending
                    }
                )
            }
            .sorted { $0.dayStart > $1.dayStart }
    }
}

enum HistoryDayFormatting {
    static func title(for dayStart: Date, calendar: Calendar = .current, now: Date = Date(),
                      locale: Locale? = nil) -> String
    {
        let effectiveLocale = locale ?? calendar.locale ?? .current
        if calendar.isDate(dayStart, inSameDayAs: now) {
            return String(localized: "history.day_today", locale: effectiveLocale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(dayStart, inSameDayAs: yesterday)
        {
            return String(localized: "history.day_yesterday", locale: effectiveLocale)
        }
        return dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(effectiveLocale))
    }
}

/// One day card: relative day, item count and a preview of the names.
private struct HistoryDayRow: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let group: HistoryDayGroup

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    dayTitle
                    itemCount
                    namesPreview
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        dayTitle
                        namesPreview
                    }
                    Spacer(minLength: 0)
                    itemCount
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("history.day_a11y \(group.title(locale: locale)) \(countText) \(group.namesPreview)")
        )
    }

    private var dayTitle: some View {
        Text(group.title(locale: locale))
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private var itemCount: some View {
        Text("history.items_count \(group.items.count)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var namesPreview: some View {
        Text(group.namesPreview)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .truncationMode(.tail)
    }

    private var countText: String {
        String(localized: "history.items_count \(group.items.count)", locale: locale)
    }
}
