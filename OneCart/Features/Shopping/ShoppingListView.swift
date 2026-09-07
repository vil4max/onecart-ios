import SwiftUI

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

    private var suggestions: [String] {
        CartSuggestionsEngine.suggestions(
            from: model.history,
            currentCartProducts: products,
            query: draftName,
            defaults: CartSuggestionsEngine.defaultEssentials(
                languageCode: model.preferences.language.languageCode
            )
        )
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
                            cartAllPurchasedHeroCard
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
            .animation(.snappy, value: purchasedCount)
            .scrollContentBackground(.hidden)
            .background(OneCartPalette.background.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                if !products.isEmpty || isComposingNewItem {
                    cartProgressStrip
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.canEdit {
                    Color.clear.frame(height: 72)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if model.canEdit {
                    CartAddFAB(accent: model.preferences.accentColor) {
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
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                String(format: String(localized: "cart.suggestion_chip_a11y %@"), item)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
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
                onToggle: {
                    let willCompleteCart = !product.isPurchasedValue && toBuyProducts.count == 1
                    if willCompleteCart, !hasCelebratedCurrentCompletion {
                        hasCelebratedCurrentCompletion = true
                        CartHaptics.success()
                        confettiTrigger += 1
                    }
                    Task {
                        await model.togglePurchased(product)
                    }
                },
                onBeginEdit: {
                    beginEditing(product)
                },
                onSubmitEdit: {
                    Task { await commitEdit() }
                }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if model.canEdit, !product.isPurchasedValue {
                    Button(role: .destructive) {
                        Task { await model.deleteProduct(product) }
                    } label: {
                        Label("common.delete", systemImage: "trash")
                    }
                    .tint(OneCartPalette.danger)
                }
            }
        }
    }

    private var cartProgressStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if isAllPurchased {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(OneCartPalette.primaryAccent)
                        Text("cart.all_purchased_title")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneCartPalette.primaryAccent)
                    }
                } else {
                    Text(
                        String(localized: "cart.progress_completed \(purchasedCount) \(products.count)")
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

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
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneCartPalette.background)
    }

    private var cartAllPurchasedHeroCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
                .padding(.top, 4)

            Text("cart.all_purchased_title")
                .font(.headline.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)

            Text("cart.all_purchased_subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                cancelNewItemComposer()
            }
            return
        }

        draftName = ""
        isComposingNewItem = true
        await Task.yield()
        focusedField = .compose
    }

    @MainActor
    private func beginEditing(_ product: ProductEntity) {
        guard model.canEdit, let productID = product.id, !isAddingDraft, !isSavingEdit else { return }
        isComposingNewItem = false
        draftName = ""
        editingProductID = productID
        editName = product.displayName
        Task { @MainActor in
            await Task.yield()
            focusedField = .edit
        }
    }

    @MainActor
    private func cancelNewItemComposer() {
        isComposingNewItem = false
        draftName = ""
        focusedField = nil
    }

    @MainActor
    private func addSuggestedItem(_ name: String) async {
        guard model.canEdit else { return }
        guard let list = model.lists.first(where: { $0.id == listID }) else { return }

        CartHaptics.light()
        let draft = ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: 0,
            note: ""
        )
        _ = await model.addProduct(to: list, draft: draft)
        hasCelebratedCurrentCompletion = false
        draftName = ""
        isComposingNewItem = true
        focusedField = .compose
    }

    @MainActor
    private func commitDraftProduct(startAnother: Bool) async {
        guard model.canEdit, !isAddingDraft else { return }
        guard !trimmedDraft.isEmpty else {
            cancelNewItemComposer()
            return
        }
        guard let list = model.lists.first(where: { $0.id == listID }) else { return }

        isAddingDraft = true
        let name = trimmedDraft
        let draft = ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: 0,
            note: ""
        )
        let succeeded = await model.addProduct(to: list, draft: draft)
        isAddingDraft = false

        guard succeeded else {
            focusedField = .compose
            return
        }

        hasCelebratedCurrentCompletion = false
        draftName = ""
        if startAnother {
            isComposingNewItem = true
            await Task.yield()
            focusedField = .compose
        } else {
            cancelNewItemComposer()
        }
    }

    @MainActor
    private func commitEdit() async {
        guard model.canEdit, !isSavingEdit else { return }
        guard let productID = editingProductID,
              let product = products.first(where: { $0.id == productID })
        else {
            editingProductID = nil
            focusedField = nil
            return
        }
        guard !trimmedEditName.isEmpty else {
            // Empty rename + Done: discard edit, hide keyboard, keep original item.
            editingProductID = nil
            editName = ""
            focusedField = nil
            return
        }

        if trimmedEditName == product.displayName {
            editingProductID = nil
            focusedField = nil
            return
        }

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
        editingProductID = nil
        focusedField = nil
    }
}
