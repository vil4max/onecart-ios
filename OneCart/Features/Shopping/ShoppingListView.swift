import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject private var model: AppModel
    let listID: UUID

    @State private var showingAddProduct = false
    @State private var editingProduct: ProductEntity?
    @State private var isCompletingPurchase = false
    @State private var toastMessage: String?

    init(listID: UUID) {
        self.listID = listID
    }

    private var list: ShoppingListEntity? {
        model.lists.first { $0.id == listID }
    }

    private var products: [ProductEntity] {
        model.products(inListID: listID)
    }

    private var toBuyProducts: [ProductEntity] {
        products.filter { !$0.isPurchasedValue }
    }

    private var inTrolleyProducts: [ProductEntity] {
        products.filter(\.isPurchasedValue)
    }

    private var purchasedCount: Int {
        inTrolleyProducts.count
    }

    private var emptyCartMessage: String {
        if model.access?.isOwner == true {
            return "\(String(localized: "home.empty_hint")) \(String(localized: "home.empty_hint_share"))"
        }
        return String(localized: "home.empty_hint")
    }

    var body: some View {
        Group {
            if list != nil {
                List {
                    if !model.canEdit {
                        Section {
                            ReadOnlyBanner()
                        }
                    }

                    if products.isEmpty {
                        Section {
                            EmptyCard(
                                image: "cart.badge.plus",
                                title: String(localized: "cart.empty_title"),
                                message: emptyCartMessage
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } else {
                        if !toBuyProducts.isEmpty {
                            Section("cart.section_to_buy") {
                                productRows(toBuyProducts)
                            }
                        }

                        if !inTrolleyProducts.isEmpty {
                            Section("cart.section_in_trolley") {
                                productRows(inTrolleyProducts)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .animation(.snappy, value: purchasedCount)
                .scrollContentBackground(.hidden)
                .background(OneCartPalette.background.ignoresSafeArea())
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !products.isEmpty {
                        cartProgressStrip
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    cartPeerActions
                }
                .refreshable {
                    await model.syncCart(reason: .pull)
                }
                .disabled(model.isBusy)
                .overlay {
                    if model.isBusy {
                        CartBusyOverlay(
                            messageKey: isCompletingPurchase ? "cart.completing" : "cart.updating"
                        )
                    }
                }
                .overlay(alignment: .top) {
                    if let toastMessage {
                        Text(toastMessage)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                OneCartPalette.surface,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: toastMessage)
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
            } else {
                ContentUnavailableViewCompat(
                    image: "questionmark.folder",
                    title: String(localized: "cart.list_unavailable_title"),
                    message: String(localized: "cart.list_unavailable_message")
                )
            }
        }
    }

    @ViewBuilder
    private func productRows(_ items: [ProductEntity]) -> some View {
        ForEach(items, id: \.objectID) { product in
            ProductRow(
                product: product,
                canEdit: model.canEdit,
                onToggle: {
                    Task {
                        await model.togglePurchased(product)
                    }
                },
                onEdit: {
                    editingProduct = product
                }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if model.canEdit {
                    Button(role: .destructive) {
                        Task { await model.deleteProduct(product) }
                    } label: {
                        Label("common.delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var cartProgressStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(
                    String(localized: "cart.progress_collected \(purchasedCount) \(products.count)")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if model.familyMembers.count >= 2 {
                    Button {
                        model.showFamilyManagement()
                    } label: {
                        Text("cart.together \(model.familyMembers.count)")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OneCartPalette.primaryAccent)
                }
            }

            ProgressView(
                value: Double(purchasedCount),
                total: Double(max(products.count, 1))
            )
            .tint(OneCartPalette.primary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneCartPalette.background.opacity(0.96))
    }

    private var cartPeerActions: some View {
        HStack(spacing: 16) {
            if purchasedCount > 0, model.canEdit {
                CartPeerActionButton(
                    systemName: "checkmark",
                    accessibilityLabel: String(localized: "cart.complete_button")
                ) {
                    Task { await runCompletePurchase() }
                }
                .disabled(model.isBusy)
            }

            Spacer(minLength: 0)

            if model.canEdit {
                CartPeerActionButton(
                    systemName: "plus",
                    accessibilityLabel: String(localized: "cart.add_a11y")
                ) {
                    showingAddProduct = true
                }
                .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(OneCartPalette.background.opacity(0.96))
    }

    @MainActor
    private func runCompletePurchase() async {
        let movingCount = purchasedCount
        guard movingCount > 0 else { return }
        isCompletingPurchase = true
        defer { isCompletingPurchase = false }
        guard let list = model.lists.first(where: { $0.id == listID }) else { return }
        await model.completePurchasedItems(list)
        guard purchasedCount == 0 else { return }
        let message = String(localized: "cart.moved_to_history \(movingCount)")
        toastMessage = message
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        if toastMessage == message {
            toastMessage = nil
        }
    }
}

private struct CartPeerActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(OneCartPalette.primary, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ProductPurchaseToggle: View {
    let isPurchased: Bool
    let canEdit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPurchased ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPurchased ? OneCartPalette.primary : Color.secondary.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
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

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.body)
                        .strikethrough(product.isPurchasedValue)
                        .foregroundStyle(product.isPurchasedValue ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !productSubtitle.isEmpty {
                        Text(productSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)

            ProductPurchaseToggle(
                isPurchased: product.isPurchasedValue,
                canEdit: canEdit,
                action: onToggle
            )
        }
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
