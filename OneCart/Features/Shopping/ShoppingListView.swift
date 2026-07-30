import SwiftUI

private enum CartNameFocus: Hashable {
    case compose
    case edit
}

struct ShoppingListView: View {
    @EnvironmentObject private var model: AppModel
    let listID: UUID

    @State private var isComposingNewItem = false
    @State private var draftName = ""
    @State private var editingProductID: UUID?
    @State private var editName = ""
    @FocusState private var focusedField: CartNameFocus?
    @State private var isAddingDraft = false
    @State private var isSavingEdit = false

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

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEditName: String {
        editName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsEmptyCard: Bool {
        products.isEmpty && !isComposingNewItem
    }

    private var emptyCartMessage: String {
        if model.access?.isOwner == true {
            return "\(String(localized: "home.empty_hint")) \(String(localized: "home.empty_hint_share"))"
        }
        return String(localized: "home.empty_hint")
    }

    private var isInlineBusy: Bool {
        isAddingDraft || isSavingEdit || isComposingNewItem || editingProductID != nil
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

                    if showsEmptyCard {
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
                        if isComposingNewItem || !toBuyProducts.isEmpty {
                            Section("cart.section_to_buy") {
                                if isComposingNewItem {
                                    newItemComposerRow
                                }
                                productRows(toBuyProducts)
                            }
                        }

                        if !inTrolleyProducts.isEmpty {
                            Section {
                                productRows(inTrolleyProducts)
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
                        CartAddFAB {
                            Task { await beginNewItem() }
                        }
                        .disabled(isAddingDraft || (model.isBusy && !isComposingNewItem))
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
            } else {
                ContentUnavailableViewCompat(
                    image: "questionmark.folder",
                    title: String(localized: "cart.list_unavailable_title"),
                    message: String(localized: "cart.list_unavailable_message")
                )
            }
        }
    }

    private var newItemComposerRow: some View {
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
    }

    private func productRows(_ items: [ProductEntity]) -> some View {
        ForEach(items, id: \.objectID) { product in
            ProductRow(
                product: product,
                canEdit: model.canEdit,
                isEditing: product.id == editingProductID,
                editName: $editName,
                editFocused: $focusedField,
                isSavingEdit: isSavingEdit,
                onToggle: {
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
                focusedField = .compose
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
    private func commitDraftProduct(startAnother: Bool) async {
        guard model.canEdit, !isAddingDraft else { return }
        guard !trimmedDraft.isEmpty else {
            focusedField = .compose
            return
        }
        guard let list = model.lists.first(where: { $0.id == listID }) else { return }

        isAddingDraft = true
        let name = trimmedDraft
        let before = Set(model.products(inListID: listID).compactMap(\.id))
        let draft = ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: 0,
            note: ""
        )
        await model.addProduct(to: list, draft: draft)
        isAddingDraft = false

        let after = Set(model.products(inListID: listID).compactMap(\.id))
        guard !after.subtracting(before).isEmpty else {
            focusedField = .compose
            return
        }

        draftName = ""
        if startAnother {
            isComposingNewItem = true
            await Task.yield()
            focusedField = .compose
        } else {
            isComposingNewItem = false
            focusedField = nil
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
            focusedField = .edit
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

private struct CartAddFAB: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(OneCartPalette.primary, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "cart.add_a11y"))
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

private struct CartCategoryThumbnail: View {
    let category: ProductCategory
    let isDimmed: Bool

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(OneCartPalette.primaryAccent)
            .frame(width: 40, height: 40)
            .background(
                OneCartPalette.primarySoft,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(isDimmed ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

private struct ProductRow: View {
    let product: ProductEntity
    let canEdit: Bool
    let isEditing: Bool
    @Binding var editName: String
    var editFocused: FocusState<CartNameFocus?>.Binding
    let isSavingEdit: Bool
    let onToggle: () -> Void
    let onBeginEdit: () -> Void
    let onSubmitEdit: () -> Void

    private var resolvedCategory: ProductCategory {
        let name = isEditing ? editName : product.displayName
        let inferred = ProductCategory.inferred(from: name)
        if inferred != .other {
            return inferred
        }
        return product.categoryValue
    }

    var body: some View {
        HStack(spacing: 12) {
            CartCategoryThumbnail(
                category: resolvedCategory,
                isDimmed: product.isPurchasedValue
            )

            if isEditing {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("cart.add_placeholder", text: $editName)
                        .font(.body)
                        .focused(editFocused, equals: .edit)
                        .submitLabel(.done)
                        .onSubmit(onSubmitEdit)
                        .disabled(isSavingEdit)

                    Text(resolvedCategory.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button(action: onBeginEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.displayName)
                            .font(.body)
                            .strikethrough(product.isPurchasedValue)
                            .foregroundStyle(product.isPurchasedValue ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(resolvedCategory.localizedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !productSubtitle.isEmpty {
                            Text(productSubtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
            }

            ProductPurchaseToggle(
                isPurchased: product.isPurchasedValue,
                canEdit: canEdit && !isEditing,
                action: onToggle
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var productSubtitle: String {
        if product.isPurchasedValue {
            if let purchasedByName = product.purchasedByName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !purchasedByName.isEmpty
            {
                return String(localized: "cart.in_trolley_by \(purchasedByName)")
            }
            return String(localized: "cart.in_trolley")
        }
        if let createdByName = product.createdByName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !createdByName.isEmpty
        {
            return String(localized: "cart.added_by \(createdByName)")
        }
        return ""
    }
}
