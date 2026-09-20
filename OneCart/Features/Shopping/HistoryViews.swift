import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppSession

    private var dayGroups: [HistoryDayGroup] {
        HistoryDayGroup.groups(from: model.history)
    }

    var body: some View {
        // Grouping dedupes and sorts the whole history; evaluate it once per body pass.
        let groups = dayGroups
        NavigationStack {
            List {
                if groups.isEmpty {
                    Section {
                        EmptyCard(
                            image: "clock",
                            title: "history.empty_title",
                            message: "history.empty_message"
                        )
                    } footer: {
                        howItWorksFooter
                    }
                } else {
                    // Read-only by requirement: rows carry no swipe actions and no delete.
                    Section {
                        ForEach(groups) { group in
                            NavigationLink {
                                HistoryDayDetailView(group: group)
                            } label: {
                                HistoryDayRow(group: group)
                            }
                        }

                        if model.historyHasMore {
                            Button("history.show_more") {
                                model.loadMoreHistory()
                            }
                        }
                    } footer: {
                        howItWorksFooter
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("history.nav_title")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var howItWorksFooter: some View {
        Text("history.how_it_works")
    }
}

struct HistoryDayGroup: Identifiable {
    let dayStart: Date
    let items: [HistoryItemEntity]

    var id: Date {
        dayStart
    }

    func title(locale: Locale? = nil) -> String {
        HistoryDayFormatting.title(for: dayStart, locale: locale)
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

private struct HistoryDayRow: View {
    @Environment(\.locale) private var locale
    let group: HistoryDayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title(locale: locale))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("history.items_count \(group.items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(productNamesLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var productNamesLine: String {
        group.items.map(\.displayName).joined(separator: ", ")
    }
}
