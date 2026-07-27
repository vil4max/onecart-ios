import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var viewModel: ShoppingViewModel

    init(model: AppModel) {
        _viewModel = StateObject(wrappedValue: ShoppingViewModel(session: model))
    }

    /// Stable household cart list: prefer the general (no-store) list, else oldest active.
    private var primaryListID: UUID? {
        let lists = model.activeLists
        if let general = lists.first(where: { $0.store == nil }) {
            return general.id
        }
        return lists
            .sorted { lhs, rhs in
                (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
            }
            .first?
            .id
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.activeFamilySpace == nil {
                    HomeConnectingCartPanel()
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(OneCartPalette.background.ignoresSafeArea())
                        .navigationTitle(model.cartTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .task {
                            await viewModel.ensureHouseholdCartIfNeeded()
                        }
                } else if let listID = primaryListID {
                    ShoppingListView(listID: listID)
                } else {
                    ScrollView {
                        HomeEmptyCartPanel(
                            cartName: model.cartTitle
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .refreshable {
                        await model.refreshFromServer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(OneCartPalette.background.ignoresSafeArea())
                    .navigationTitle(model.cartTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .task {
                        await viewModel.ensureHouseholdCartIfNeeded()
                    }
                }
            }
        }
    }
}

private struct HomeConnectingCartPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("home.connecting_cart")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

private struct HomeEmptyCartPanel: View {
    let cartName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cartName)
                .font(.title2.bold())
            Text("home.empty_hint")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .padding(.top, 8)
    }
}

private struct HomePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

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
                        await model.refreshFromServer()
                    }
                    .background(OneCartPalette.background.ignoresSafeArea())

                    bottomBar
                }
                .navigationTitle(model.cartTitle)
                .navigationBarTitleDisplayMode(.inline)
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

// Minimal add/rename: product name only. Quantity/unit/category use defaults.

struct QuickAddProductSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    let listID: UUID
    var product: ProductEntity?

    @State private var name: String
    @State private var isSaving = false

    init(listID: UUID, product: ProductEntity? = nil) {
        self.listID = listID
        self.product = product
        _name = State(initialValue: product?.displayName ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEditing: Bool {
        product != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("cart.add_placeholder", text: $name)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        OneCartPalette.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .disabled(isSaving)

                Button {
                    save()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text(isEditing ? "common.save" : "cart.add_to_cart")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OneCartPrimaryButtonStyle())
                .disabled(trimmedName.isEmpty || isSaving)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "cart.edit_title" : "cart.add_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { dismiss() }
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                nameFocused = true
            }
        }
        .oneCartMediumSheet()
    }

    private func save() {
        guard model.canEdit, !trimmedName.isEmpty, !isSaving else { return }
        guard let list = model.lists.first(where: { $0.id == listID }) else {
            dismiss()
            return
        }

        isSaving = true
        let draft = ProductDraft(
            name: trimmedName,
            quantity: product?.quantityValue ?? 1,
            unit: product?.unitValue ?? .piece,
            category: product?.categoryValue ?? ProductCategory.inferred(from: trimmedName),
            estimatedPrice: product?.estimatedPriceValue ?? 0,
            note: product?.noteValue ?? "",
            imageURL: product?.imageURL,
            sourceURL: product?.sourceURL,
            originalPrice: product?.originalPrice?.doubleValue,
            loyaltyPrice: product?.loyaltyPrice?.doubleValue,
            catalogFetchedAt: product?.catalogFetchedAt,
            promotionEndsAt: product?.promotionEndsAt
        )

        Task {
            defer { isSaving = false }
            if let product {
                let productID = product.id
                await model.updateProduct(product, draft: draft)
                if let productID,
                   model.products(inListID: listID).contains(where: { $0.id == productID })
                {
                    dismiss()
                }
            } else {
                let before = Set(model.products(inListID: listID).compactMap(\.id))
                await model.addProduct(to: list, draft: draft)
                let after = Set(model.products(inListID: listID).compactMap(\.id))
                guard !after.subtracting(before).isEmpty else { return }
                dismiss()
            }
        }
    }
}

// Kept for any remaining call sites; forwards to the quick name editor.

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingDelete: PurchaseHistoryEntity?
    @State private var visibleCount = 30

    private var groupedHistory: [(month: Date, entries: [PurchaseHistoryEntity])] {
        let visibleEntries = Array(model.history.prefix(visibleCount))
        let grouped = Dictionary(grouping: visibleEntries) { entry in
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

                        if visibleCount < model.history.count {
                            Button {
                                visibleCount = min(visibleCount + 30, model.history.count)
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

private struct HistoryDetailView: View {
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

private struct HistoryProductRow: View {
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

struct ReadOnlyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("cart.read_only_title")
                    .font(.subheadline.bold())
                Text("cart.read_only_message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .oneCartCard()
    }
}

struct EmptyCard: View {
    let image: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: image)
                .font(.system(size: 28))
                .foregroundColor(OneCartPalette.primary)
                .frame(width: 52, height: 52)
                .background(
                    OneCartPalette.primarySoft,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

struct ContentUnavailableViewCompat: View {
    let image: String
    let title: String
    let message: String

    var body: some View {
        EmptyCard(image: image, title: title, message: message)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneCartPalette.background)
    }
}

private extension View {
    func oneCartMediumSheet() -> some View {
        presentationDetents([.medium])
            .presentationDragIndicator(.visible)
    }
}
