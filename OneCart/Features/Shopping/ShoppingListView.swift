import SwiftUI

// swiftlint:disable:next type_body_length
struct ShoppingListView: View {
    @EnvironmentObject private var model: AppSession
    let listID: UUID

    @State private var isComposingNewItem = false
    @State private var draftName = ""
    @State private var editingProductID: UUID?
    @State private var editName = ""
    @FocusState private var focusedField: CartNameFocus?
    @State private var isAddingDraft = false
    @State private var isSavingEdit = false
    @State private var confettiTrigger = 0
    @State private var hasCelebratedCurrentCompletion = false
    @State private var suggestions: [String] = []
    @State private var duplicateHighlightID: UUID?

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

    private var toBuyCategorySections: [(category: ProductCategory, items: [ProductEntity])] {
        ProductCategory.groupedSections(from: toBuyProducts) { $0.categoryValue }
    }

    private var inTrolleyProducts: [ProductEntity] {
        products.filter(\.isPurchasedValue)
    }

    private var purchasedCount: Int {
        inTrolleyProducts.count
    }

    private var isAllPurchased: Bool {
        !products.isEmpty && toBuyProducts.isEmpty
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
        if list != nil {
            ScrollViewReader { proxy in
                List {
                    if !model.canEdit {
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
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
                .scrollContentBackground(.hidden)
                .background(OneCartPalette.background.ignoresSafeArea())
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !products.isEmpty || isComposingNewItem {
                        CartProgressStrip(
                            isAllPurchased: isAllPurchased,
                            purchasedCount: purchasedCount,
                            totalCount: products.count,
                            familyMembersCount: model.familyMembers.count,
                            onManageFamily: { model.showFamilyManagement() }
                        )
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if model.canEdit {
                        Color.clear.frame(height: 72)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if model.canEdit {
                        CartAddFAB(
                            accent: model.preferences.accentColor,
                            isComposing: isComposingNewItem && trimmedDraft.isEmpty
                        ) {
                            Task { await beginNewItem() }
                        }
                        .disabled(isAddingDraft || (model.isBusy && !isComposingNewItem))
                        .keyboardShortcut("n", modifiers: .command)
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                    }
                }
                .refreshable {
                    await model.syncCart(reason: .pull)
                }
                .disabled(model.isBusy && !isInlineBusy)
                .overlay {
                    if model.isBusy, !isInlineBusy {
                        CartBusyOverlay(messageKey: "cart.updating")
                    }
                }
                .overlay {
                    CartConfettiView(trigger: confettiTrigger)
                }
                .navigationTitle(model.cartTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if model.isCartSyncing {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityLabel(Text("cart.updating"))
                        }
                    }
                }
                .background {
                    Button("") {
                        Task { await model.syncCart(reason: .pull) }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
                }
                .task {
                    await model.syncCart(reason: .appear)
                }
                .onChange(of: draftName) {
                    updateSuggestions()
                }
                .onChange(of: model.contentRevision) {
                    if isComposingNewItem {
                        updateSuggestions()
                    }
                }
                .onChange(of: duplicateHighlightID) {
                    guard let target = duplicateHighlightID else { return }
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
                        get: { model.sharedCartRemovedMessage != nil },
                        set: {
                            if !$0 {
                                model.dismissSharedCartRemovedMessage()
                            }
                        }
                    )
                ) {
                    Button("common.ok", role: .cancel) {
                        model.dismissSharedCartRemovedMessage()
                    }
                } message: {
                    Text(model.sharedCartRemovedMessage ?? "")
                }
            }
        } else {
            ContentUnavailableViewCompat(
                image: "questionmark.folder",
                title: String(localized: "cart.list_unavailable_title"),
                message: String(localized: "cart.list_unavailable_message")
            )
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
                    .accessibilityLabel(String(localized: "cart.add_a11y"))
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
                                String(format: String(localized: "cart.suggestion_chip_a11y %@"), item)
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
                canEdit: model.canEdit,
                isEditing: product.id == editingProductID,
                editName: $editName,
                editFocused: $focusedField,
                isSavingEdit: isSavingEdit,
                showsCategoryLabel: showsCategoryLabel,
                isHighlighted: product.id == duplicateHighlightID,
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
                if model.canEdit, !product.isPurchasedValue {
                    Button(role: .destructive) {
                        if editingProductID == product.id {
                            focusedField = nil
                            editingProductID = nil
                        }
                        Task { await model.deleteProduct(product) }
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
        let willCompleteCart = !product.isPurchasedValue && toBuyProducts.count == 1
        if willCompleteCart, !hasCelebratedCurrentCompletion {
            hasCelebratedCurrentCompletion = true
            CartHaptics.success()
            confettiTrigger += 1
        }
        if product.isPurchasedValue {
            hasCelebratedCurrentCompletion = false
        }
        Task {
            if isEditing {
                await commitEdit()
            }
            await model.togglePurchased(product)
        }
    }

    @MainActor
    private func beginNewItem() async {
        guard model.canEdit, !isAddingDraft, !isSavingEdit else { return }

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
        guard model.canEdit, let productID = product.id, !isAddingDraft, !isSavingEdit else { return }
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
        suggestions = CartSuggestionsEngine.suggestions(
            from: model.history,
            currentCartProducts: products,
            query: draftName,
            defaults: CartSuggestionsEngine.defaultEssentials(
                languageCode: model.preferences.language.languageCode
            )
        )
    }

    @MainActor
    private func addSuggestedItem(_ name: String) async {
        guard model.canEdit else { return }
        guard let list = model.lists.first(where: { $0.id == listID }) else { return }

        CartHaptics.light()
        let existingIDs = Set(products.compactMap(\.id))
        let draft = ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: 0,
            note: ""
        )
        if let productID = await model.addProduct(to: list, draft: draft),
           existingIDs.contains(productID)
        {
            flashDuplicateRow(productID)
        }
        hasCelebratedCurrentCompletion = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            draftName = ""
            isComposingNewItem = true
        }
        updateSuggestions()
        focusedField = .compose
    }

    @MainActor
    private func commitDraftProduct(startAnother: Bool) async {
        guard model.canEdit, !isAddingDraft else { return }
        guard !trimmedDraft.isEmpty else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                cancelNewItemComposer()
            }
            return
        }
        guard let list = model.lists.first(where: { $0.id == listID }) else { return }

        isAddingDraft = true
        let name = trimmedDraft
        let existingIDs = Set(products.compactMap(\.id))
        let draft = ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: 0,
            note: ""
        )
        guard let productID = await model.addProduct(to: list, draft: draft) else {
            isAddingDraft = false
            focusedField = .compose
            return
        }
        isAddingDraft = false

        // Duplicate protection: the name is already on the cart — reveal the
        // existing row instead of adding a second line.
        if existingIDs.contains(productID) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                draftName = ""
                cancelNewItemComposer()
            }
            flashDuplicateRow(productID)
            return
        }

        hasCelebratedCurrentCompletion = false
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
    private func flashDuplicateRow(_ productID: UUID) {
        withAnimation(.easeInOut(duration: 0.3)) {
            duplicateHighlightID = productID
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if duplicateHighlightID == productID {
                withAnimation(.easeInOut(duration: 0.45)) {
                    duplicateHighlightID = nil
                }
            }
        }
    }

    @MainActor
    private func commitEdit() async {
        guard model.canEdit, !isSavingEdit else { return }
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
        guard trimmedEditName != product.displayName else { return }

        isSavingEdit = true
        let draft = ProductDraft(
            name: trimmedEditName,
            quantity: product.quantityValue,
            unit: product.unitValue,
            category: ProductCategory.inferred(from: trimmedEditName),
            estimatedPrice: product.estimatedPriceValue,
            note: product.noteValue,
            imageURL: product.imageURL,
            sourceURL: product.sourceURL,
            originalPrice: product.originalPrice?.doubleValue,
            loyaltyPrice: product.loyaltyPrice?.doubleValue,
            catalogFetchedAt: product.catalogFetchedAt,
            promotionEndsAt: product.promotionEndsAt
        )
        await model.updateProduct(product, draft: draft)
        isSavingEdit = false
    }
}
