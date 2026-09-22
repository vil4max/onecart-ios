import SwiftUI

/// One archived day, sectioned by category like the cart. Read-only: no swipe, edit or
/// delete affordance exists here (REQ-SHELL-020, REQ-HIST-050).
struct HistoryDayDetailView: View {
    @Environment(\.locale) private var locale
    let viewModel: HistoryViewModel
    let group: HistoryDayGroup

    var body: some View {
        // Regrouping the whole history is not free; resolve the live group once per body pass.
        let liveGroup = viewModel.liveGroup(for: group)
        let sections = liveGroup.categorySections
        List {
            ForEach(Array(sections.enumerated()), id: \.element.category) { offset, section in
                Section {
                    ForEach(section.items, id: \.objectID) { item in
                        HistoryProductRow(item: item)
                    }
                } header: {
                    Label(section.category.localizedTitleKey, systemImage: section.category.symbolName)
                } footer: {
                    if offset == sections.count - 1 {
                        Text("history.read_only_footer")
                            .accessibilityIdentifier("history.read_only_footer")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(liveGroup.title(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One archived line: category tile, name and who bought it; the same shape as `CartProductRow`
/// without its controls.
struct HistoryProductRow: View {
    let item: HistoryItemEntity

    var body: some View {
        HStack(spacing: 12) {
            CartCategoryThumbnail(category: item.categoryValue, isDimmed: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if let boughtBy = item.purchasedByName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !boughtBy.isEmpty
                {
                    Text("history.bought_by \(boughtBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.item_row")
    }
}
