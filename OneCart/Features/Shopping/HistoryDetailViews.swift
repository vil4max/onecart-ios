import SwiftUI

struct HistoryDayDetailView: View {
    @EnvironmentObject private var model: AppSession
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let group: HistoryDayGroup

    private var liveGroup: HistoryDayGroup {
        HistoryDayGroup.groups(from: model.history)
            .first { calendar.isDate($0.dayStart, inSameDayAs: group.dayStart) }
            ?? group
    }

    private var calendar: Calendar {
        .current
    }

    private var isRegular: Bool {
        horizontalSizeClass == .regular
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320, maximum: .infinity), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            Group {
                if isRegular {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        rowsContent
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        rowsContent
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(OneCartPalette.background.ignoresSafeArea())
        .navigationTitle(liveGroup.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rowsContent: some View {
        ForEach(liveGroup.items, id: \.objectID) { item in
            HistoryProductRow(item: item)
        }
    }
}

struct HistoryProductRow: View {
    let item: HistoryItemEntity

    var body: some View {
        HStack(spacing: 12) {
            OfficialProductThumbnail(
                category: item.categoryValue,
                size: 52
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
                    Text(String(localized: "history.bought_by \(boughtBy)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
