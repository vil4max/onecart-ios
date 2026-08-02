import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppSession

    private var dayGroups: [HistoryDayGroup] {
        HistoryDayGroup.groups(from: model.history)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("history.how_it_works")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isStaticText)

                    if dayGroups.isEmpty {
                        EmptyCard(
                            image: "clock",
                            title: String(localized: "history.empty_title"),
                            message: String(localized: "history.empty_message")
                        )
                    } else {
                        ForEach(dayGroups) { group in
                            NavigationLink {
                                HistoryDayDetailView(group: group)
                            } label: {
                                HistoryDayCard(group: group)
                            }
                            .buttonStyle(HomePressButtonStyle())
                        }

                        if model.historyHasMore {
                            Button {
                                model.loadMoreHistory()
                            } label: {
                                Text("history.show_more")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OneCartSecondaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("history.nav_title")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct HistoryDayGroup: Identifiable {
    let dayStart: Date
    let items: [HistoryItemEntity]

    var id: Date {
        dayStart
    }

    var title: String {
        HistoryDayFormatting.title(for: dayStart)
    }

    static func groups(
        from entries: [PurchaseHistoryEntity],
        calendar: Calendar = .current
    ) -> [HistoryDayGroup] {
        let items = entries.flatMap(\.sortedItems)
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
    static func title(for dayStart: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        if calendar.isDate(dayStart, inSameDayAs: now) {
            return String(localized: "history.day_today")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(dayStart, inSameDayAs: yesterday)
        {
            return String(localized: "history.day_yesterday")
        }
        return dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct HistoryDayCard: View {
    let group: HistoryDayGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("history.items_count \(group.items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(productNamesLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var productNamesLine: String {
        group.items.map(\.displayName).joined(separator: ", ")
    }
}
