import SwiftUI

struct HistoryDayDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let group: HistoryDayGroup
    @State private var confirmingDelete = false

    private var liveGroup: HistoryDayGroup {
        HistoryDayGroup.groups(from: model.history)
            .first { calendar.isDate($0.dayStart, inSameDayAs: group.dayStart) }
            ?? group
    }

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(liveGroup.items, id: \.objectID) { item in
                    HistoryProductRow(item: item)
                }

                if model.canEdit, !liveGroup.items.isEmpty {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("history.delete_day", systemImage: "trash")
                            .font(.headline)
                            .foregroundColor(OneCartPalette.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(
                                OneCartPalette.danger.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(HomePressButtonStyle())
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(OneCartPalette.background.ignoresSafeArea())
        .navigationTitle(liveGroup.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("history.delete_day_title", isPresented: $confirmingDelete) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                Task {
                    await model.deleteHistoryItems(liveGroup.items)
                    dismiss()
                }
            }
        } message: {
            Text("history.delete_day_message")
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
