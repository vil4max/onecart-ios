import SwiftUI

struct ShoppingListView: View {
    let viewModel: CartViewModel

    @State private var renamingProduct: ProductEntity?
    @State private var renameDraft = ""
    @State private var showsBusyOverlay = false

    /// Session work shorter than this never shows the blocking overlay, so a local cart
    /// mutation does not flash it while membership or account operations still do.
    private static let busyOverlayDelay: Duration = .milliseconds(400)

    private var emptyCartMessage: LocalizedStringKey {
        "\(Text("home.empty_hint")) \(Text("home.empty_hint_share"))"
    }

    var body: some View {
        if viewModel.primaryList != nil {
            cartList
        } else {
            ContentUnavailableView {
                Label("cart.list_unavailable_title", systemImage: "questionmark.folder")
            } description: {
                Text("cart.list_unavailable_message")
            }
        }
    }

    private var cartList: some View {
        ScrollViewReader { proxy in
            List {
                if !viewModel.canEdit {
                    Section {
                        ReadOnlyBanner()
                    }
                }

                if viewModel.showsProgress {
                    Section {
                        CartProgressHeader(viewModel: viewModel)
                    }
                }

                ForEach(viewModel.toBuySections, id: \.category) { section in
                    Section {
                        productRows(section.items, showsCategoryLabel: false)
                    } header: {
                        Label(section.category.localizedTitleKey, systemImage: section.category.symbolName)
                    }
                }

                if viewModel.isAllPurchased {
                    Section {
                        CartAllPurchasedHeroCard()
                    }
                }

                if !viewModel.completedProducts.isEmpty {
                    Section {
                        productRows(viewModel.completedProducts, showsCategoryLabel: true)
                    } header: {
                        Label("cart.section_in_trolley", systemImage: "checkmark.circle")
                    } footer: {
                        Text("cart.trolley_history_hint")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if viewModel.isEmpty {
                    ContentUnavailableView {
                        Label("cart.empty_title", systemImage: "cart.badge.plus")
                    } description: {
                        Text(emptyCartMessage)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.snappy, value: viewModel.contentRevision)
            .animation(.easeInOut(duration: 0.35), value: viewModel.duplicateHighlightID)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.canEdit {
                    CartAddComposer(viewModel: viewModel)
                }
            }
            .refreshable {
                await viewModel.sync(reason: .pull)
            }
            .disabled(showsBusyOverlay)
            .overlay {
                if showsBusyOverlay {
                    CartBusyOverlay(messageKey: "cart.updating")
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsBusyOverlay)
            .overlay {
                CartConfettiView(trigger: viewModel.confettiTrigger)
            }
            .sensoryFeedback(.success, trigger: viewModel.confettiTrigger)
            .navigationTitle(viewModel.cartTitle)
            .toolbar {
                cartToolbar
            }
            .background {
                Button("") {
                    Task { await viewModel.sync(reason: .pull) }
                }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
            }
            .task {
                await viewModel.sync(reason: .appear)
            }
            .task(id: viewModel.isBusy) {
                guard viewModel.isBusy else {
                    showsBusyOverlay = false
                    return
                }
                try? await Task.sleep(for: Self.busyOverlayDelay)
                if !Task.isCancelled, viewModel.isBusy {
                    showsBusyOverlay = true
                }
            }
            .onChange(of: viewModel.duplicateHighlightID) {
                guard let target = viewModel.duplicateHighlightID else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(Optional(target), anchor: .center)
                }
            }
            .alert(
                UserAlertKind.error.title,
                isPresented: Binding(
                    get: { viewModel.sharedCartRemovedMessage != nil },
                    set: {
                        if !$0 {
                            viewModel.dismissSharedCartRemovedMessage()
                        }
                    }
                )
            ) {
                Button("common.ok", role: .cancel) {
                    viewModel.dismissSharedCartRemovedMessage()
                }
            } message: {
                Text(viewModel.sharedCartRemovedMessage ?? "")
            }
            .alert(
                "cart.rename_title",
                isPresented: Binding(
                    get: { renamingProduct != nil },
                    set: {
                        if !$0 {
                            renamingProduct = nil
                        }
                    }
                ),
                presenting: renamingProduct
            ) { product in
                TextField("cart.add_placeholder", text: $renameDraft)
                Button("common.cancel", role: .cancel) {
                    renamingProduct = nil
                }
                Button("cart.rename_save") {
                    let name = renameDraft
                    renamingProduct = nil
                    Task { _ = await viewModel.rename(product, to: name) }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var cartToolbar: some ToolbarContent {
        if viewModel.isCartSyncing {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("cart.updating"))
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.showFamilyManagement()
            } label: {
                // A plain HStack: toolbar labels collapse to their icon and would drop the count.
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                    Text(viewModel.familyMembersCount, format: .number)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(Text("cart.members_a11y \(viewModel.familyMembersCount)"))
            .accessibilityIdentifier("cart.members")
        }
    }

    private func productRows(
        _ items: [ProductEntity],
        showsCategoryLabel: Bool
    ) -> some View {
        ForEach(items, id: \.objectID) { product in
            CartProductRow(
                product: product,
                canEdit: viewModel.canEdit,
                showsCategoryLabel: showsCategoryLabel,
                isHighlighted: product.id == viewModel.duplicateHighlightID,
                onToggle: {
                    Task { await viewModel.togglePurchased(product) }
                },
                onRename: {
                    beginRename(product)
                }
            )
            .id(product.id)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if viewModel.canEdit {
                    Button {
                        Task { await viewModel.togglePurchased(product) }
                    } label: {
                        if product.isPurchasedValue {
                            Label("cart.swipe_to_buy", systemImage: "arrow.uturn.backward")
                        } else {
                            Label("cart.swipe_complete", systemImage: "checkmark")
                        }
                    }
                    .tint(product.isPurchasedValue ? .orange : OneCartPalette.primary)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                // Completed lines cannot be deleted; uncheck first (REQ-CART-050).
                if viewModel.canEdit, !product.isPurchasedValue {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteProduct(product) }
                    } label: {
                        Label("common.delete", systemImage: "trash")
                    }
                    .tint(OneCartPalette.danger)
                }
            }
            .contextMenu {
                if viewModel.canEdit {
                    Button("cart.rename_action", systemImage: "pencil") {
                        beginRename(product)
                    }
                }
            }
        }
    }

    private func beginRename(_ product: ProductEntity) {
        guard viewModel.canEdit else { return }
        renameDraft = product.displayName
        renamingProduct = product
    }
}
