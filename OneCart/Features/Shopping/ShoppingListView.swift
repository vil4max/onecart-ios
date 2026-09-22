import SwiftUI

// swiftlint:disable:next type_body_length
struct ShoppingListView: View {
    let viewModel: CartViewModel

    @State private var isComposingNewItem = false
    @State private var draftName = ""
    @State private var editingProductID: UUID?
    @State private var editName = ""
    @FocusState private var focusedField: CartNameFocus?
    @State private var isAddingDraft = false
    @State private var isSavingEdit = false
    @State private var suggestions: [String] = []

    private var products: [ProductEntity] {
        viewModel.products
    }

    private var toBuyProducts: [ProductEntity] {
        viewModel.toBuyProducts
    }

    private var toBuyCategorySections: [(category: ProductCategory, items: [ProductEntity])] {
        viewModel.toBuySections
    }

    private var inTrolleyProducts: [ProductEntity] {
        viewModel.completedProducts
    }

    private var purchasedCount: Int {
        viewModel.purchasedCount
    }

    private var isAllPurchased: Bool {
        viewModel.isAllPurchased
    }

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEditName: String {
        editName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsEmptyCard: Bool {
        products.isEmpty && !isComposingNewItem
    }

    private var emptyCartMessage: LocalizedStringKey {
        "\(Text("home.empty_hint")) \(Text("home.empty_hint_share"))"
    }

    private var isInlineBusy: Bool {
        isAddingDraft || isSavingEdit || isComposingNewItem || editingProductID != nil
    }

    var body: some View {
        if viewModel.primaryList != nil {
            ScrollViewReader { proxy in
                List {
                    if !viewModel.canEdit {
                        Section {
                            ReadOnlyBanner()
                        }
                    }

                    if showsEmptyCard {
                        Section {
                            EmptyCard(
                                image: "cart.badge.plus",
                                title: "cart.empty_title",
                                message: emptyCartMessage
                            )
                        }
                    } else {
                        if isComposingNewItem {
                            Section {
                                newItemComposerRow
                            } header: {
                                if toBuyProducts.isEmpty {
                                    Text("cart.section_to_buy")
                                }
                            }
                        }

                        ForEach(toBuyCategorySections, id: \.category) { section in
                            Section {
                                productRows(section.items, showsCategoryLabel: false)
                            } header: {
                                Label(section.category.localizedTitleKey, systemImage: section.category.symbolName)
                            }
                        }

                        if isAllPurchased, !isComposingNewItem {
                            Section {
                                CartAllPurchasedHeroCard()
                            }
                        }

                        if !inTrolleyProducts.isEmpty {
                            Section {
                                productRows(inTrolleyProducts, showsCategoryLabel: true)
                            } header: {
                                Text("cart.section_in_trolley")
                            } footer: {
                                Text("cart.trolley_history_hint")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isComposingNewItem)
                .animation(.spring(response: 0.40, dampingFraction: 0.82), value: purchasedCount)
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: toBuyProducts.map(\.id))
                .animation(.spring(response: 0.42, dampingFraction: 0.82), value: inTrolleyProducts.map(\.id))
                .animation(.spring(response: 0.40, dampingFraction: 0.82), value: isAllPurchased)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showsEmptyCard)
                .animation(.easeInOut(duration: 0.35), value: viewModel.duplicateHighlightID)
                .safeAreaBar(edge: .top, spacing: 0) {
                    if !products.isEmpty || isComposingNewItem {
                        CartProgressStrip(
                            isAllPurchased: isAllPurchased,
                            purchasedCount: purchasedCount,
                            totalCount: products.count,
                            familyMembersCount: viewModel.familyMembersCount,
                            onManageFamily: { viewModel.showFamilyManagement() }
                        )
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if viewModel.canEdit {
                        Color.clear.frame(height: 72)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if viewModel.canEdit {
                        CartAddFAB(
                            accent: viewModel.accentColor,
                            isComposing: isComposingNewItem && trimmedDraft.isEmpty
                        ) {
                            Task { await beginNewItem() }
                        }
                        .disabled(isAddingDraft || (viewModel.isBusy && !isComposingNewItem))
                        .keyboardShortcut("n", modifiers: .command)
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                    }
                }
                .refreshable {
                    await viewModel.sync(reason: .pull)
                }
                .disabled(viewModel.isBusy && !isInlineBusy)
                .overlay {
                    if viewModel.isBusy, !isInlineBusy {
                        CartBusyOverlay(messageKey: "cart.updating")
                    }
                }
                .overlay {
                    CartConfettiView(trigger: viewModel.confettiTrigger)
                }
                .sensoryFeedback(.success, trigger: viewModel.confettiTrigger)
                .navigationTitle(viewModel.cartTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if viewModel.isCartSyncing {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityLabel(Text("cart.updating"))
                        }
                    }
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
                .onChange(of: draftName) {
                    updateSuggestions()
                }
                .onChange(of: viewModel.contentRevision) {
                    if isComposingNewItem {
                        updateSuggestions()
                    }
                }
                .onChange(of: viewModel.duplicateHighlightID) {
                    guard let target = viewModel.duplicateHighlightID else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(Optional(target), anchor: .center)
                    }
                }
                .onChange(of: focusedField) {
                    if focusedField == nil, editingProductID != nil {
                        Task { await commitEdit() }
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
            }
        } else {
            ContentUnavailableView {
                Label("cart.list_unavailable_title", systemImage: "questionmark.folder")
            } description: {
                Text("cart.list_unavailable_message")
            }
        }
    }

    private var newItemComposerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CartCategoryThumbnail(
                    category: ProductCategory.inferred(from: draftName),
                    isDimmed: false
                )

                TextField("cart.add_placeholder", text: $draftName)
                    .font(.body)
                    .focused($focusedField, equals: .compose)
                    .submitLabel(.done)
                    .onSubmit { Task { await commitDraftProduct(startAnother: false) } }
                    .disabled(isAddingDraft)
                    .accessibilityLabel(Text("cart.add_a11y"))
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { item in
                            Button {
                                Task { await addSuggestedItem(item) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.caption2.weight(.bold))
                                    Text(item)
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(OneCartPalette.primaryAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(OneCartPalette.primarySoft)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(HomePressButtonStyle())
                            .accessibilityLabel(
                                Text("cart.suggestion_chip_a11y \(item)")
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .animation(.easeInOut(duration: 0.25), value: suggestions)
            }
        }
        .padding(.vertical, 4)
    }

    private func productRows(
        _ items: [ProductEntity],
        showsCategoryLabel: Bool
    ) -> some View {
        ForEach(items, id: \.objectID) { product in
            ProductRow(
                product: product,
                canEdit: viewModel.canEdit,
                isEditing: product.id == editingProductID,
                editName: $editName,
                editFocused: $focusedField,
                isSavingEdit: isSavingEdit,
                showsCategoryLabel: showsCategoryLabel,
                isHighlighted: product.id == viewModel.duplicateHighlightID,
                onToggle: {
                    togglePurchased(product)
                },
                onBeginEdit: {
                    beginEditing(product)
                },
                onSubmitEdit: {
                    Task { await commitEdit() }
                }
            )
            .id(product.id)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if viewModel.canEdit, !product.isPurchasedValue {
                    Button(role: .destructive) {
                        if editingProductID == product.id {
                            focusedField = nil
                            editingProductID = nil
                        }
                        Task { await viewModel.deleteProduct(product) }
                    } label: {
                        Label("common.delete", systemImage: "trash")
                    }
                    .tint(OneCartPalette.danger)
                }
            }
        }
    }

    @MainActor
    private func togglePurchased(_ product: ProductEntity) {
        let isEditing = editingProductID != nil
        focusedField = nil
        if isComposingNewItem, trimmedDraft.isEmpty {
            cancelNewItemComposer()
        }
        Task {
            if isEditing {
                await commitEdit()
            }
            await viewModel.togglePurchased(product)
        }
    }

    @MainActor
    private func beginNewItem() async {
        guard viewModel.canEdit, !isAddingDraft, !isSavingEdit else { return }

        if editingProductID != nil {
            await commitEdit()
        }

        if isComposingNewItem {
            if !trimmedDraft.isEmpty {
                await commitDraftProduct(startAnother: true)
            } else {
                // Empty name + Done / FAB: dismiss composer, do not save a blank row.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    cancelNewItemComposer()
                }
            }
            return
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            draftName = ""
            isComposingNewItem = true
        }
        updateSuggestions()
        await Task.yield()
        focusedField = .compose
    }

    @MainActor
    private func beginEditing(_ product: ProductEntity) {
        guard viewModel.canEdit, let productID = product.id, !isAddingDraft, !isSavingEdit else { return }
        Task { @MainActor in
            if editingProductID != nil, editingProductID != productID {
                await commitEdit()
            }
            isComposingNewItem = false
            draftName = ""
            editingProductID = productID
            editName = product.displayName
            await Task.yield()
            focusedField = .edit
        }
    }

    @MainActor
    private func cancelNewItemComposer() {
        isComposingNewItem = false
        draftName = ""
        suggestions = []
        focusedField = nil
    }

    @MainActor
    private func updateSuggestions() {
        suggestions = viewModel.suggestions(matching: draftName)
    }

    @MainActor
    private func addSuggestedItem(_ name: String) async {
        guard viewModel.canEdit else { return }

        CartHaptics.light()
        _ = await viewModel.addItem(named: name)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            draftName = ""
            isComposingNewItem = true
        }
        updateSuggestions()
        focusedField = .compose
    }

    @MainActor
    private func commitDraftProduct(startAnother: Bool) async {
        guard viewModel.canEdit, !isAddingDraft else { return }
        guard !trimmedDraft.isEmpty else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                cancelNewItemComposer()
            }
            return
        }

        isAddingDraft = true
        let outcome = await viewModel.addItem(named: trimmedDraft)
        isAddingDraft = false

        switch outcome {
        case .rejected:
            focusedField = .compose
            return
        case .duplicate:
            // The name is already on the cart: the ViewModel flashes the existing
            // row instead of adding a second line; only the composer closes here.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                draftName = ""
                cancelNewItemComposer()
            }
            return
        case .added:
            break
        }

        CartHaptics.light()

        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            draftName = ""
            if startAnother {
                isComposingNewItem = true
            } else {
                cancelNewItemComposer()
            }
        }

        if startAnother {
            updateSuggestions()
            await Task.yield()
            focusedField = .compose
        }
    }

    @MainActor
    private func commitEdit() async {
        guard viewModel.canEdit, !isSavingEdit else { return }
        defer {
            editingProductID = nil
            focusedField = nil
        }
        guard let productID = editingProductID,
              let product = products.first(where: { $0.id == productID })
        else { return }
        guard !trimmedEditName.isEmpty else {
            editName = ""
            return
        }

        isSavingEdit = true
        _ = await viewModel.rename(product, to: trimmedEditName)
        isSavingEdit = false
    }
}
