import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingDelete: PurchaseHistoryEntity?

    private var groupedHistory: [(month: Date, entries: [PurchaseHistoryEntity])] {
        let grouped = Dictionary(grouping: model.history) { entry in
            let components = Calendar.current.dateComponents(
                [.year, .month],
                from: entry.purchaseDate
            )
            return Calendar.current.date(from: components) ?? entry.purchaseDate
        }
        return grouped
            .map { (month: $0.key, entries: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.history.isEmpty {
                        EmptyCard(
                            image: "clock",
                            title: String(localized: "history.empty_title"),
                            message: String(localized: "history.empty_message")
                        )
                    } else {
                        ForEach(groupedHistory, id: \.month) { group in
                            Section {
                                VStack(spacing: 12) {
                                    ForEach(group.entries, id: \.objectID) { entry in
                                        NavigationLink {
                                            HistoryDetailView(entry: entry)
                                        } label: {
                                            HistoryEntryCard(entry: entry)
                                        }
                                        .buttonStyle(HomePressButtonStyle())
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                pendingDelete = entry
                                            } label: {
                                                Label("history.delete_entry", systemImage: "trash")
                                            }
                                            .disabled(!model.canEdit)
                                        }
                                    }
                                }
                            } header: {
                                Text(group.month.formatted(.dateTime.month(.wide).year()))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                            }
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
            .alert(
                "history.delete_title",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("common.cancel", role: .cancel) { pendingDelete = nil }
                Button("common.delete", role: .destructive) {
                    if let pendingDelete {
                        Task { await model.deleteHistory(pendingDelete) }
                    }
                    pendingDelete = nil
                }
            }
        }
    }
}

private struct HistoryEntryCard: View {
    let entry: PurchaseHistoryEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entry.purchaseDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.bold))
                    .foregroundColor(OneCartPalette.primaryAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        OneCartPalette.primarySoft,
                        in: Capsule(style: .continuous)
                    )
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Image(systemName: "cart.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(OneCartPalette.primaryAccent)
                    .frame(width: 48, height: 48)
                    .background(
                        OneCartPalette.primarySoft,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.membersDisplay)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("history.items_count \(entry.sortedItems.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
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
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
