import SwiftUI

struct HistoryDayDetailView: View {
    @EnvironmentObject private var model: AppSession
    @Environment(\.locale) private var locale
    let group: HistoryDayGroup

    private var liveGroup: HistoryDayGroup {
        HistoryDayGroup.groups(from: model.history)
            .first { calendar.isDate($0.dayStart, inSameDayAs: group.dayStart) }
            ?? group
    }

    private var calendar: Calendar {
        .current
    }

    var body: some View {
        // Regrouping the whole history is not free; resolve the live group once per body pass.
        let liveGroup = liveGroup
        List {
            Section {
                ForEach(liveGroup.items, id: \.objectID) { item in
                    HistoryProductRow(item: item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(liveGroup.title(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryProductRow: View {
    let item: HistoryItemEntity

    var body: some View {
        HStack(spacing: 12) {
            OfficialProductThumbnail(
                category: item.categoryValue,
                size: 40
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let boughtBy = item.purchasedByName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !boughtBy.isEmpty
                {
                    Text("history.bought_by \(boughtBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
