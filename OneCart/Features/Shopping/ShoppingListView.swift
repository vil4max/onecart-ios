import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject private var model: AppModel
    let listID: UUID

    @State private var showingAddProduct = false
    @State private var editingProduct: ProductEntity?
    @State private var confirmingCompletion = false
    @State private var pendingDelete: ProductEntity?

    init(listID: UUID) {
        self.listID = listID
    }

    private var list: ShoppingListEntity? {
        model.lists.first { $0.id == listID }
    }

    private var products: [ProductEntity] {
        model.products(inListID: listID)
    }

    private var remainingCount: Int {
        products.filter { !$0.isPurchasedValue }.count
    }

    private var purchasedCount: Int {
        products.count - remainingCount
    }

    private var emptyCartMessage: String {
        if model.access?.isOwner == true {
            return "\(String(localized: "home.empty_hint")) \(String(localized: "home.empty_hint_share"))"
        }
        return String(localized: "home.empty_hint")
    }

    var body: some View {
        Group {
            if let list {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !model.canEdit {
                                ReadOnlyBanner()
                            }

                            if !products.isEmpty {
                                listSummaryCard
                            }

                            if products.isEmpty {
                                EmptyCard(
                                    image: "cart.badge.plus",
                                    title: String(localized: "cart.empty_title"),
                                    message: emptyCartMessage
                                )
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(products, id: \.objectID) { product in
                                        ProductRow(
                                            product: product,
                                            canEdit: model.canEdit,
                                            onToggle: {
                                                Task { await model.togglePurchased(product) }
                                            },
                                            onEdit: {
                                                editingProduct = product
                                            },
                                            onDelete: {
                                                pendingDelete = product
                                            }
                                        )
                                    }
                                }
                            }

                            if !products.isEmpty {
                                VStack(spacing: 8) {
                                    Button {
                                        confirmingCompletion = true
                                    } label: {
                                        Text("cart.complete_button")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(OneCartPrimaryButtonStyle())
                                    .disabled(purchasedCount == 0 || !model.canEdit)
                                    .opacity(purchasedCount > 0 && model.canEdit ? 1 : 0.5)

                                    Text(
                                        String(localized: "cart.complete_caption")
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, model.canEdit ? 120 : 28)
                    }
                    .refreshable {
                        await model.syncCart(reason: .pull)
                    }
                    .background(OneCartPalette.background.ignoresSafeArea())

                    bottomBar
                }
                .navigationTitle(model.cartTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        CartNavSyncTitle(title: model.cartTitle, isSyncing: model.isCartSyncing)
                    }
                }
                .task {
                    await model.syncCart(reason: .appear)
                }
                .alert(
                    "common.app_name",
                    isPresented: Binding(
                        get: { model.sharedCartRemovedMessage != nil },
                        set: { if !$0 { model.dismissSharedCartRemovedMessage() } }
                    )
                ) {
                    Button("common.ok", role: .cancel) {
                        model.dismissSharedCartRemovedMessage()
                    }
                } message: {
                    Text(model.sharedCartRemovedMessage ?? "")
                }
                .sheet(isPresented: $showingAddProduct) {
                    QuickAddProductSheet(listID: listID)
                }
                .sheet(item: $editingProduct) { product in
                    QuickAddProductSheet(listID: listID, product: product)
                }
                .alert("cart.complete_confirm_title", isPresented: $confirmingCompletion) {
                    Button("common.cancel", role: .cancel) {}
                    Button("cart.complete_button") {
                        Task { await model.completePurchasedItems(list) }
                    }
                } message: {
                    Text("cart.complete_confirm_message \(purchasedCount)")
                }
                .alert(
                    "cart.delete_item_title",
                    isPresented: Binding(
                        get: { pendingDelete != nil },
                        set: { if !$0 { pendingDelete = nil } }
                    )
                ) {
                    Button("common.cancel", role: .cancel) { pendingDelete = nil }
                    Button("common.delete", role: .destructive) {
                        if let pendingDelete {
                            Task { await model.deleteProduct(pendingDelete) }
                        }
                        pendingDelete = nil
                    }
                } message: {
                    Text(pendingDelete?.displayName ?? String(localized: "cart.delete_item_fallback"))
                }

            } else {
                ContentUnavailableViewCompat(
                    image: "questionmark.folder",
                    title: String(localized: "cart.list_unavailable_title"),
                    message: String(localized: "cart.list_unavailable_message")
                )
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if model.canEdit {
                Button {
                    showingAddProduct = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(OneCartPalette.primary, in: Circle())
                }
                .accessibilityLabel(String(localized: "cart.add_a11y"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var listSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("cart.section_title")
                .font(.headline)

            Text(
                String(localized: "cart.trolley_progress \(purchasedCount) \(products.count) \(remainingCount)")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ProgressView(
                value: Double(purchasedCount),
                total: Double(products.count)
            )
            .tint(OneCartPalette.primary)

            if purchasedCount == 0 {
                Text("cart.trolley_hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.familyMembers.count >= 2 {
                Button {
                    model.showFamilyManagement()
                } label: {
                    Text("cart.together \(model.familyMembers.count)")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OneCartPalette.primaryAccent)
            }
        }
        .padding(16)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct ProductPurchaseToggle: View {
    let isPurchased: Bool
    let canEdit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isPurchased ? OneCartPalette.primary : Color.secondary.opacity(0.45),
                        lineWidth: 2
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isPurchased ? OneCartPalette.primary : Color.clear)
                    )
                if isPurchased {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressButtonStyle())
        .disabled(!canEdit)
        .accessibilityLabel(
            isPurchased ? String(localized: "cart.unmark_trolley_a11y") : String(localized: "cart.mark_in_trolley_a11y")
        )
        .accessibilityAddTraits(isPurchased ? [.isSelected] : [])
    }
}

private struct ProductRow: View {
    @EnvironmentObject private var model: AppModel
    let product: ProductEntity
    let canEdit: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProductPurchaseToggle(
                isPurchased: product.isPurchasedValue,
                canEdit: canEdit,
                action: onToggle
            )

            OfficialProductThumbnail(
                category: product.categoryValue,
                isPurchased: product.isPurchasedValue,
                size: 52
            )

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.body.weight(.semibold))
                        .strikethrough(product.isPurchasedValue)
                        .foregroundStyle(product.isPurchasedValue ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(productSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("common.edit", systemImage: "pencil")
                }
                .disabled(!canEdit)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("common.delete", systemImage: "trash")
                }
                .disabled(!canEdit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .disabled(!canEdit)
            .accessibilityLabel(String(localized: "cart.more_actions_a11y"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            product.isPurchasedValue
                ? OneCartPalette.surface.opacity(0.72)
                : OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    product.isPurchasedValue
                        ? Color.primary.opacity(0.03)
                        : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
    }

    private var productSubtitle: String {
        guard product.isPurchasedValue else { return "" }
        if model.familyMembers.count >= 2,
           let purchasedByName = product.purchasedByName,
           !purchasedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return String(localized: "cart.in_trolley_by \(purchasedByName)")
        }
        return String(localized: "cart.in_trolley")
    }
}
