import SwiftUI

struct HistoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: PurchaseHistoryEntity
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("history.date")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(entry.purchaseDate.formatted(date: .long, time: .shortened))
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("history.members")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(entry.membersDisplay)
                            .font(.body.weight(.medium))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    OneCartPalette.surface,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("history.items")
                            .font(.title3.bold())
                        Spacer()
                        Text("\(entry.sortedItems.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Color(.tertiarySystemFill),
                                in: Capsule(style: .continuous)
                            )
                    }

                    ForEach(entry.sortedItems, id: \.objectID) { item in
                        HistoryProductRow(item: item)
                    }
                }

                if model.canEdit {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("history.delete_entry", systemImage: "trash")
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
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(OneCartPalette.background.ignoresSafeArea())
        .navigationTitle("history.session_title")
        .navigationBarTitleDisplayMode(.inline)
        .alert("history.delete_title", isPresented: $confirmingDelete) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                Task {
                    await model.deleteHistory(entry)
                    dismiss()
                }
            }
        } message: {
            Text("history.delete_message")
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

            Text(item.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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

