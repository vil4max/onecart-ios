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
        NavigationView {
            Group {
                if model.activeFamilySpace == nil {
                    HomeConnectingCartPanel()
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(OneCartPalette.background.ignoresSafeArea())
                        .navigationTitle(
                            model.activeFamilySpace?.displayName
                                ?? String(localized: "tab.home")
                        )
                        .navigationBarTitleDisplayMode(.inline)
                        .task {
                            await viewModel.ensureHouseholdCartIfNeeded()
                        }
                } else if let listID = primaryListID {
                    ShoppingListView(listID: listID)
                } else {
                    HomeEmptyCartPanel(
                        cartName: model.activeFamilySpace?.displayName
                            ?? String(localized: "cart.default_title")
                    )
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(OneCartPalette.background.ignoresSafeArea())
                    .navigationTitle(
                        model.activeFamilySpace?.displayName
                            ?? String(localized: "tab.home")
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .task {
                        await viewModel.ensureHouseholdCartIfNeeded()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
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

struct AddListSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = "Список покупок"
    @State private var selectedStoreID: UUID?

    private let titlePresets = ["Продукты", "Еженедельный", "Хозтовары", "Аптека", "Дача", "Праздник"]

    private let storeColumns = [
        GridItem(.adaptive(minimum: 135), spacing: 10),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Field 1: List Title
                    VStack(alignment: .leading, spacing: 10) {
                        Text("НАЗВАНИЕ СПИСКА")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(OneCartPalette.primarySoft)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "cart.fill")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(OneCartPalette.primaryStrong)
                            }

                            TextField("Название списка", text: $title)
                                .font(.system(size: 16, weight: .semibold))

                            if !title.isEmpty {
                                Button {
                                    title = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(OneCartPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )

                        // Presets
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(titlePresets, id: \.self) { preset in
                                    Button {
                                        title = preset
                                    } label: {
                                        Text(preset)
                                            .font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(
                                                title == preset ? OneCartPalette.primarySoft : OneCartPalette.surface,
                                                in: Capsule()
                                            )
                                            .foregroundColor(title == preset ? OneCartPalette.primaryStrong : .primary)
                                            .overlay(
                                                Capsule()
                                                    .stroke(
                                                        title == preset ? OneCartPalette.primary : Color(.separator)
                                                            .opacity(0.5),
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                        }
                    }

                    // Field 2: Store Picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("МАГАЗИН")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: storeColumns, spacing: 10) {
                            // General option
                            StorePickerCardView(
                                isSelected: selectedStoreID == nil,
                                title: "Без магазина",
                                subtitle: "Общий список",
                                iconName: "bag.fill"
                            ) {
                                selectedStoreID = nil
                            }

                            // Store options
                            ForEach(model.stores, id: \.objectID) { store in
                                let isSelected = selectedStoreID == store.id
                                StorePickerCardView(
                                    isSelected: isSelected,
                                    title: store.displayName,
                                    subtitle: store.address,
                                    storeName: store.displayName,
                                    fallbackIcon: store.icon ?? "storefront",
                                    fallbackColorHex: store.colorHex ?? "#34785B"
                                ) {
                                    selectedStoreID = store.id
                                    title = "Покупки в \(store.displayName)"
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("Новый список")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .font(.system(size: 16, weight: .regular))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let store = model.stores.first { $0.id == selectedStoreID }
                        Task {
                            await model.addList(title: title, store: store)
                            dismiss()
                        }
                    } label: {
                        Text("Создать")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? OneCartPalette.primary.opacity(0.4)
                                    : OneCartPalette.primary,
                                in: Capsule()
                            )
                            .foregroundColor(.white)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct StorePickerCardView: View {
    let isSelected: Bool
    let title: String
    let subtitle: String?
    var iconName: String?
    var storeName: String?
    var fallbackIcon: String = "storefront"
    var fallbackColorHex: String = "#34785B"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    if let storeName {
                        StoreBrandMark(
                            storeName: storeName,
                            fallbackIcon: fallbackIcon,
                            fallbackColorHex: fallbackColorHex,
                            size: 42
                        )
                    } else if let iconName {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(OneCartPalette.primarySoft)
                                .frame(width: 42, height: 42)
                            Image(systemName: iconName)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(OneCartPalette.primaryStrong)
                        }
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(OneCartPalette.primary)
                            .background(Circle().fill(Color.white).padding(2))
                            .offset(x: 6, y: -4)
                    }
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                isSelected ? OneCartPalette.primarySoft.opacity(0.6) : OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? OneCartPalette.primary : Color(.separator).opacity(0.4),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(HomePressButtonStyle())
    }
}

struct ShoppingListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let listID: UUID

    @State private var showingAddProduct = false
    @State private var showingOfficialCatalog = false
    @State private var editingProduct: ProductEntity?
    @State private var confirmingCompletion = false
    @State private var confirmingDeleteList = false
    @State private var pendingDelete: ProductEntity?

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

    private var estimatedTotal: Double {
        products.reduce(0) { $0 + $1.estimatedPriceValue }
    }

    private var catalogBrand: StoreBrand? {
        guard let storeName = list?.store?.displayName else { return nil }
        return StoreBrand.matching(storeName)
    }

    var body: some View {
        Group {
            if let list {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !model.canEdit {
                            ReadOnlyBanner()
                        }

                        listSummaryCard

                        if products.isEmpty {
                            EmptyCard(
                                image: "cart.badge.plus",
                                title: String(localized: "cart.empty_title"),
                                message: catalogBrand == nil
                                    ? String(localized: "home.empty_hint")
                                    : "Откройте официальный каталог и добавьте товар вместе с фото и ценой."
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Товары")
                                        .font(.title3.bold())
                                    Spacer()
                                    Text("\(products.count)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Color(.tertiarySystemFill),
                                            in: Capsule(style: .continuous)
                                        )
                                }

                                ForEach(products, id: \.objectID) { product in
                                    ProductRow(
                                        product: product,
                                        lists: model.activeLists,
                                        canEdit: model.canEdit,
                                        onToggle: {
                                            Task { await model.togglePurchased(product) }
                                        },
                                        onEdit: {
                                            editingProduct = product
                                        },
                                        onDelete: {
                                            pendingDelete = product
                                        },
                                        onMove: { destination in
                                            Task {
                                                await model.moveProduct(
                                                    product,
                                                    to: destination
                                                )
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        if !products.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    confirmingCompletion = true
                                } label: {
                                    Label("Завершить покупку", systemImage: "checkmark.seal.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(OneCartPrimaryButtonStyle())
                                .disabled(!model.canEdit)
                                .opacity(model.canEdit ? 1 : 0.5)

                                Text("Товары сохранятся в истории, а для магазина появится новый пустой список.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .background(OneCartPalette.background.ignoresSafeArea())
                .navigationTitle(
                    list.store?.displayName
                        ?? model.activeFamilySpace?.displayName
                        ?? list.displayTitle
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 8) {
                            Button {
                                if catalogBrand == nil {
                                    showingAddProduct = true
                                } else {
                                    showingOfficialCatalog = true
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.body.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .disabled(!model.canEdit)
                            .accessibilityLabel(
                                catalogBrand == nil ? "Добавить товар" : "Каталог товаров"
                            )

                            Menu {
                                Button {
                                    showingAddProduct = true
                                } label: {
                                    Label("Добавить вручную", systemImage: "square.and.pencil")
                                }
                                .disabled(!model.canEdit)

                                if catalogBrand != nil {
                                    Button {
                                        showingOfficialCatalog = true
                                    } label: {
                                        Label("Каталог товаров", systemImage: "storefront")
                                    }
                                    .disabled(!model.canEdit)
                                }

                                if model.activeLists.count > 1 {
                                    Divider()

                                    Button(role: .destructive) {
                                        confirmingDeleteList = true
                                    } label: {
                                        Label("Удалить список", systemImage: "trash")
                                    }
                                    .disabled(!model.canEdit)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAddProduct) {
                    ProductEditorSheet(listID: listID, product: nil)
                }
                .sheet(isPresented: $showingOfficialCatalog) {
                    if let catalogBrand {
                        OfficialCatalogSheet(listID: listID, brand: catalogBrand)
                    }
                }
                .sheet(item: $editingProduct) { product in
                    ProductEditorSheet(listID: listID, product: product)
                }
                .alert("Завершить покупку?", isPresented: $confirmingCompletion) {
                    Button("Отмена", role: .cancel) {}
                    Button("Завершить") {
                        Task { await model.completeList(list) }
                    }
                } message: {
                    Text("Текущие товары перейдут в историю покупок.")
                }
                .alert("Удалить этот список?", isPresented: $confirmingDeleteList) {
                    Button("Отмена", role: .cancel) {}
                    Button("Удалить", role: .destructive) {
                        Task {
                            await model.deleteList(list)
                            dismiss()
                        }
                    }
                } message: {
                    Text("Список со всеми его товарами будет безвозвратно удалён.")
                }
                .alert(
                    "Удалить товар?",
                    isPresented: Binding(
                        get: { pendingDelete != nil },
                        set: { if !$0 { pendingDelete = nil } }
                    )
                ) {
                    Button("Отмена", role: .cancel) { pendingDelete = nil }
                    Button("Удалить", role: .destructive) {
                        if let pendingDelete {
                            Task { await model.deleteProduct(pendingDelete) }
                        }
                        pendingDelete = nil
                    }
                } message: {
                    Text(pendingDelete?.displayName ?? "Товар будет удалён из списка.")
                }
            } else {
                ContentUnavailableViewCompat(
                    image: "questionmark.folder",
                    title: "Список недоступен",
                    message: "Он мог быть удалён или перемещён владельцем."
                )
            }
        }
    }

    private var listSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("В списке")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if products.isEmpty {
                    Text("Пока пусто")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(purchasedCount) из \(products.count) куплено")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !products.isEmpty {
                GeometryReader { geo in
                    let progress = Double(purchasedCount) / Double(products.count)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(OneCartPalette.primary)
                            .frame(width: max(10, geo.size.width * progress))
                    }
                }
                .frame(height: 9)
            }

            HStack(spacing: 8) {
                summaryPill(
                    value: "\(remainingCount)",
                    label: "ещё взять",
                    systemImage: "basket"
                )
                if estimatedTotal > 0 {
                    summaryPill(
                        value: estimatedTotal.oneCartCurrency,
                        label: "примерно",
                        systemImage: "banknote"
                    )
                }
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
    }

    private func summaryPill(value: String, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(OneCartPalette.primary)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            OneCartPalette.primarySoft.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private struct ProductPriceStack: View {
    let price: Double
    let originalPrice: Double?
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        if price > 0 {
            VStack(alignment: alignment, spacing: 2) {
                Text(price.oneCartCurrency)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(
                        originalPrice == nil ? .primary : OneCartPalette.danger
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let originalPrice {
                    Text(originalPrice.oneCartCurrency)
                        .font(.caption2)
                        .monospacedDigit()
                        .strikethrough(true)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(priceAccessibilityLabel)
        }
    }

    private var priceAccessibilityLabel: String {
        if let originalPrice {
            return "Цена \(price.oneCartCurrency), было \(originalPrice.oneCartCurrency)"
        }
        return "Цена \(price.oneCartCurrency)"
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
        .accessibilityLabel(isPurchased ? "Отметить как не купленное" : "Отметить как купленное")
        .accessibilityAddTraits(isPurchased ? [.isSelected] : [])
    }
}

private struct ProductRow: View {
    let product: ProductEntity
    let lists: [ShoppingListEntity]
    let canEdit: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMove: (ShoppingListEntity) -> Void

    private var moveTargets: [ShoppingListEntity] {
        lists.filter { $0.id != product.list?.id }
    }

    var body: some View {
        HStack(spacing: 12) {
            ProductPurchaseToggle(
                isPurchased: product.isPurchasedValue,
                canEdit: canEdit,
                action: onToggle
            )

            OfficialProductThumbnail(
                media: OfficialProductMedia.resolve(product: product),
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

                    if product.isCatalogPriceStale {
                        Label("Цена требует проверки", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if let promotionEndsAt = product.promotionEndsAt,
                              product.originalPriceValue != nil
                    {
                        CatalogPromotionCountdown(endsAt: promotionEndsAt, compact: true)
                    } else if let catalogFetchedAt = product.catalogFetchedAt {
                        Text("Проверено \(CatalogDateFormatter.string(from: catalogFetchedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)

            VStack(alignment: .trailing, spacing: 6) {
                ProductPriceStack(
                    price: product.estimatedPriceValue,
                    originalPrice: product.originalPriceValue
                )

                Menu {
                    Button {
                        onEdit()
                    } label: {
                        Label("Изменить", systemImage: "pencil")
                    }
                    .disabled(!canEdit)

                    if !moveTargets.isEmpty {
                        Menu {
                            ForEach(moveTargets, id: \.objectID) { list in
                                Button(list.store?.displayName ?? list.displayTitle) {
                                    onMove(list)
                                }
                            }
                        } label: {
                            Label("Переместить", systemImage: "arrow.right.square")
                        }
                        .disabled(!canEdit)
                    }

                    if let sourceURL = product.sourceURLValue {
                        Link(destination: sourceURL) {
                            Label("Проверить на сайте", systemImage: "safari")
                        }
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Удалить", systemImage: "trash")
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
                .accessibilityLabel("Ещё действия")
            }
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
        [
            "\(product.quantityValue.oneCartQuantity) \(product.unitValue.localizedName)",
            product.categoryValue.localizedName,
        ]
        .joined(separator: " · ")
    }
}

struct ProductEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let listID: UUID
    let product: ProductEntity?

    @State private var name: String
    @State private var quantity: String
    @State private var unit: ProductUnit
    @State private var category: ProductCategory
    @State private var price: String
    @State private var note: String

    init(listID: UUID, product: ProductEntity?) {
        self.listID = listID
        self.product = product
        _name = State(initialValue: product?.displayName ?? "")
        _quantity = State(
            initialValue: product.map(\.quantityValue.oneCartQuantity) ?? "1"
        )
        _unit = State(initialValue: product?.unitValue ?? .piece)
        _category = State(initialValue: product?.categoryValue ?? .other)
        _price = State(
            initialValue: product.map {
                $0.estimatedPriceValue == 0 ? "" : $0.estimatedPriceValue.oneCartQuantity
            } ?? ""
        )
        _note = State(initialValue: product?.noteValue ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Товар") {
                    TextField("Название", text: $name)
                    TextField("Количество", text: $quantity)
                        .keyboardType(.decimalPad)
                    Picker("Единица", selection: $unit) {
                        ForEach(ProductUnit.allCases) { unit in
                            Text(unit.localizedName).tag(unit)
                        }
                    }
                    Picker("Категория", selection: $category) {
                        ForEach(ProductCategory.allCases) { category in
                            Text(category.localizedName).tag(category)
                        }
                    }
                }

                if let media = officialMedia {
                    Section("Фото товара") {
                        HStack(spacing: 12) {
                            OfficialProductThumbnail(
                                media: media,
                                category: category,
                                size: 72
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Из каталога \(media.sourceName)")
                                    .font(.subheadline.weight(.semibold))
                                Text("Фото и цена сохранены в OneCart")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Дополнительно") {
                    TextField("Ориентировочная цена, ₴", text: $price)
                        .keyboardType(.decimalPad)
                    TextField("Заметка", text: $note)
                }
            }
            .navigationTitle(product == nil ? "Новый товар" : "Редактирование")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var officialMedia: OfficialProductMedia? {
        if let product {
            return OfficialProductMedia.resolve(product: product)
        }
        let storeName = model.lists.first(where: { $0.id == listID })?.store?.displayName
        return OfficialProductMedia.resolve(productName: name, storeName: storeName)
    }

    private func save() {
        guard model.canEdit else { return }
        guard let list = model.lists.first(where: { $0.id == listID }) else {
            dismiss()
            return
        }
        let draft = ProductDraft(
            name: name,
            quantity: Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 1,
            unit: unit,
            category: category,
            estimatedPrice: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0,
            note: note,
            imageURL: product?.imageURL,
            sourceURL: product?.sourceURL,
            originalPrice: product?.originalPrice?.doubleValue,
            loyaltyPrice: product?.loyaltyPrice?.doubleValue,
            catalogFetchedAt: product?.catalogFetchedAt,
            promotionEndsAt: product?.promotionEndsAt
        )
        Task {
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
                if !after.subtracting(before).isEmpty {
                    dismiss()
                }
            }
        }
    }
}

struct StoresView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewStore = false
    @State private var showingCatalog = false
    @State private var selectedBrand: StoreBrand?
    @State private var editingStore: StoreEntity?
    @State private var pendingDelete: StoreEntity?

    var body: some View {
        NavigationView {
            List {
                if !model.canEdit {
                    Section {
                        ReadOnlyBanner()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Мои магазины") {
                    if model.stores.isEmpty {
                        EmptyCard(
                            image: "storefront",
                            title: "Нет магазинов",
                            message: "Выберите сеть ниже и добавьте ближайшую точку с карты."
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(model.stores, id: \.objectID) { store in
                            Group {
                                if let listID = store.activeList?.id {
                                    NavigationLink {
                                        ShoppingListView(listID: listID)
                                    } label: {
                                        StoreRow(store: store)
                                    }
                                } else {
                                    StoreRow(store: store)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingStore = store
                                        }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = store
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                                .disabled(!model.canEdit)

                                Button {
                                    editingStore = store
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                                .tint(OneCartPalette.primary)
                                .disabled(!model.canEdit)
                            }
                        }
                    }
                }

                Section("Популярные сети") {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ],
                        spacing: 10
                    ) {
                        ForEach(StoreBrand.popular) { brand in
                            Button {
                                selectedBrand = brand
                            } label: {
                                StoreBrandCatalogButton(brand: brand)
                            }
                            .buttonStyle(.plain)
                            .disabled(!model.canEdit)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Магазины")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingCatalog = true
                        } label: {
                            Label("Найти сеть рядом", systemImage: "map")
                        }
                        Button {
                            showingNewStore = true
                        } label: {
                            Label("Добавить вручную", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!model.canEdit)
                }
            }
            .sheet(isPresented: $showingNewStore) {
                StoreEditorSheet(store: nil)
            }
            .sheet(isPresented: $showingCatalog) {
                StoreCatalogSheet()
            }
            .sheet(item: $selectedBrand) { brand in
                NavigationView {
                    StoreLocatorView(brand: brand) {
                        selectedBrand = nil
                    }
                }
            }
            .sheet(item: $editingStore) { store in
                StoreEditorSheet(store: store)
            }
            .alert(
                "Удалить магазин?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Отмена", role: .cancel) {
                    pendingDelete = nil
                }
                Button("Удалить", role: .destructive) {
                    if let pendingDelete {
                        Task { await model.deleteStore(pendingDelete) }
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("Товары останутся в группе без привязки к магазину.")
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct StoreBrandCatalogButton: View {
    let brand: StoreBrand

    var body: some View {
        HStack(spacing: 9) {
            StoreBrandMark(
                storeName: brand.name,
                fallbackIcon: brand.shortMark,
                fallbackColorHex: brand.colorHex,
                size: 38
            )
            Text(brand.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundColor(OneCartPalette.primary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(OneCartPalette.surface)
        )
    }
}

private struct StoreRow: View {
    let store: StoreEntity

    var body: some View {
        HStack(spacing: 13) {
            StoreBrandMark(
                storeName: store.displayName,
                fallbackIcon: store.displayIcon,
                fallbackColorHex: store.displayColorHex,
                size: 48
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(store.displayName)
                        .font(.headline)
                    if store.isPinnedValue {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(OneCartPalette.primary)
                    }
                }
                if let address = store.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(store.activeList.map {
                    "\($0.sortedProducts.count) товаров"
                } ?? "Нет активного списка")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct StoreEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let store: StoreEntity?

    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var address: String
    @State private var externalURL: String
    @State private var isPinned: Bool
    @State private var confirmingDeleteStore = false
    private let latitude: Double?
    private let longitude: Double?

    private let colors = [
        "#34785B", "#4F6D8A", "#9A6547", "#8B5D75", "#6D628A", "#C94747",
    ]

    init(store: StoreEntity?) {
        self.store = store
        _name = State(initialValue: store?.displayName ?? "")
        _icon = State(initialValue: store?.displayIcon ?? "")
        _colorHex = State(initialValue: store?.displayColorHex ?? "#34785B")
        _address = State(initialValue: store?.address ?? "")
        _externalURL = State(initialValue: store?.externalAppURL ?? "")
        _isPinned = State(initialValue: store?.isPinnedValue ?? false)
        latitude = store?.latitudeValue
        longitude = store?.longitudeValue
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Магазин") {
                    TextField("Название", text: $name)
                    TextField("Короткая иконка", text: $icon)
                    TextField("Адрес", text: $address)
                    TextField("Ссылка на сайт", text: $externalURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    if latitude != nil, longitude != nil {
                        Label("Точка на карте сохранена", systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundColor(OneCartPalette.primary)
                    }
                    Toggle("Закрепить", isOn: $isPinned)
                }

                Section("Цвет") {
                    HStack {
                        ForEach(colors, id: \.self) { color in
                            Button {
                                colorHex = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if colorHex == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundColor(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if store != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmingDeleteStore = true
                        } label: {
                            HStack {
                                Spacer()
                                Label("Удалить магазин", systemImage: "trash")
                                    .foregroundColor(OneCartPalette.danger)
                                Spacer()
                            }
                        }
                        .disabled(!model.canEdit)
                    }
                }
            }
            .navigationTitle(store == nil ? "Новый магазин" : "Магазин")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Удалить магазин?", isPresented: $confirmingDeleteStore) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) {
                    if let store {
                        Task {
                            await model.deleteStore(store)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("Магазин будет удалён, а его товары останутся в общем списке.")
            }
        }
    }

    private func save() {
        let normalizedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = StoreDraft(
            name: name,
            icon: normalizedIcon.isEmpty
                ? String(name.prefix(2)).uppercased()
                : normalizedIcon,
            colorHex: colorHex,
            address: address,
            latitude: latitude,
            longitude: longitude,
            externalAppURL: externalURL,
            isPinned: isPinned
        )
        Task {
            if let store {
                await model.updateStore(store, draft: draft)
            } else {
                await model.addStore(draft)
            }
            dismiss()
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingDelete: PurchaseHistoryEntity?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.history.isEmpty {
                        EmptyCard(
                            image: "clock",
                            title: "История пуста",
                            message: "Завершённые покупки появятся здесь."
                        )
                    } else {
                        ForEach(model.history, id: \.objectID) { entry in
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
                                    Label("Удалить запись", systemImage: "trash")
                                }
                                .disabled(!model.canEdit)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Удалить запись?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Отмена", role: .cancel) { pendingDelete = nil }
                Button("Удалить", role: .destructive) {
                    if let pendingDelete {
                        Task { await model.deleteHistory(pendingDelete) }
                    }
                    pendingDelete = nil
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct HistoryEntryCard: View {
    let entry: PurchaseHistoryEntity

    private var storeName: String {
        entry.store?.displayName ?? "Общий список"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(entry.purchaseDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.bold))
                    .foregroundColor(OneCartPalette.primaryStrong)
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
                if let store = entry.store {
                    StoreBrandMark(
                        storeName: store.displayName,
                        fallbackIcon: store.displayIcon,
                        fallbackColorHex: store.displayColorHex,
                        size: 48
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundColor(OneCartPalette.primaryStrong)
                        .frame(width: 48, height: 48)
                        .background(
                            OneCartPalette.primarySoft,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(storeName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(entry.sortedItems.count) товаров · \(entry.membersDisplay)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(entry.totalValue.oneCartCurrency)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundColor(OneCartPalette.primaryStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    private var storeName: String {
        entry.store?.displayName ?? "Покупка"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Дата")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(entry.purchaseDate.formatted(date: .long, time: .shortened))
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Итого")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(entry.totalValue.oneCartCurrency)
                                .font(.title3.bold())
                                .monospacedDigit()
                                .foregroundColor(OneCartPalette.primaryStrong)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Участники")
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
                        Text("Товары")
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
                        Label("Удалить запись", systemImage: "trash")
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
        .navigationTitle(storeName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Удалить запись?", isPresented: $confirmingDelete) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                Task {
                    await model.deleteHistory(entry)
                    dismiss()
                }
            }
        } message: {
            Text("Запись исчезнет из истории покупок.")
        }
    }
}

private struct HistoryProductRow: View {
    let item: HistoryItemEntity

    var body: some View {
        HStack(spacing: 12) {
            OfficialProductThumbnail(
                media: OfficialProductMedia.resolve(historyItem: item),
                category: item.categoryValue,
                size: 52
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "\(item.quantityValue.oneCartQuantity) \(item.unitValue.localizedName)"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProductPriceStack(
                price: item.estimatedPriceValue,
                originalPrice: item.originalPriceValue
            )
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
                Text("Только просмотр")
                    .font(.subheadline.bold())
                Text("Владелец не предоставил право редактирования.")
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

extension Double {
    var oneCartCurrency: String {
        formatted(
            .currency(code: "UAH")
                .locale(Locale(identifier: "uk_UA"))
                .precision(.fractionLength(0 ... 2))
        )
    }

    var oneCartQuantity: String {
        formatted(.number.precision(.fractionLength(0 ... 2)))
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
