import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAddList = false
    @State private var appeared = false

    private var overview: HomeOverview { model.homeOverview }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !model.canEdit {
                        ReadOnlyBanner()
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                    }

                    HomeMasthead(
                        familyName: model.activeFamilySpace?.displayName ?? "OneCart",
                        listCount: model.activeLists.count,
                        overview: overview
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)

                    HomeFamilyInviteRow(
                        symbol: familySymbol,
                        title: familyTitle,
                        detail: familyDetail,
                        actionTitle: familyAction
                    ) {
                        model.showFamilyManagement()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)

                    HomeListsHeader(
                        count: model.activeLists.count,
                        canAdd: model.canEdit
                    ) {
                        showingAddList = true
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    if model.activeLists.isEmpty {
                        HomeEmptyListsPanel(canEdit: model.canEdit) {
                            showingAddList = true
                        }
                        .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(model.activeLists, id: \.objectID) { list in
                                if let id = list.id {
                                    NavigationLink {
                                        ShoppingListView(listID: id)
                                    } label: {
                                        ShoppingListRow(
                                            list: list,
                                            summary: model.summary(for: id)
                                        )
                                    }
                                    .buttonStyle(HomePressButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 28)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 10)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("Главная")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddList = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(!model.canEdit)
                    .accessibilityLabel("Добавить список")
                }
            }
            .sheet(isPresented: $showingAddList) {
                AddListSheet()
            }
            .onAppear {
                guard !appeared else { return }
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.easeOut(duration: 0.28)) {
                        appeared = true
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var familySymbol: String {
        switch model.access {
        case .owner?: return "person.2"
        case .member?: return "person.2.fill"
        case nil: return "person.crop.circle"
        }
    }

    private var familyTitle: String {
        switch model.access {
        case .owner?:
            let count = max(model.familyMembers.count, 1)
            return count == 1 ? "Семья ещё не собрана" : "В семье \(count)"
        case .member?:
            return "Общий семейный список"
        case nil:
            return "Семейное пространство"
        }
    }

    private var familyDetail: String {
        switch model.access {
        case .owner?:
            return "Пригласите близких по ссылке"
        case .member?:
            return "Товары видны всем участникам"
        case nil:
            return "Настройте доступ к спискам"
        }
    }

    private var familyAction: String {
        switch model.access {
        case .owner?: return "Управлять"
        case .member?: return "Участники"
        case nil: return "Открыть"
        }
    }
}

private struct HomeMasthead: View {
    let familyName: String
    let listCount: Int
    let overview: HomeOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Семейный список")
                .font(.caption.weight(.semibold))
                .foregroundColor(OneCartPalette.primary)
                .textCase(.uppercase)

            Text(familyName)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HomeMetaStrip(items: metaItems)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metaItems: [String] {
        var items: [String] = [listsLabel]
        if overview.totalCount == 0 {
            items.append("пока без товаров")
        } else {
            items.append("куплено \(overview.purchasedCount) из \(overview.totalCount)")
            items.append(overview.estimatedTotal.oneCartCurrency)
        }
        return items
    }

    private var listsLabel: String {
        let mod10 = listCount % 10
        let mod100 = listCount % 100
        if listCount == 0 {
            return "нет списков"
        }
        if mod10 == 1, mod100 != 11 {
            return "\(listCount) список"
        }
        if (2...4).contains(mod10), !(12...14).contains(mod100) {
            return "\(listCount) списка"
        }
        return "\(listCount) списков"
    }
}

private struct HomeMetaStrip: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("·")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                }
                Text(item)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct HomeFamilyInviteRow: View {
    let symbol: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(OneCartPalette.primary)
                    .frame(width: 3)
                    .padding(.vertical, 4)

                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundColor(OneCartPalette.primaryStrong)
                        .frame(width: 36, height: 36)
                        .background(
                            OneCartPalette.primarySoft,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(OneCartPalette.primary)
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 14)
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityLabel("\(title). \(actionTitle)")
    }
}

private struct HomeListsHeader: View {
    let count: Int
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Списки")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color(.tertiarySystemFill),
                        in: Capsule(style: .continuous)
                    )
            }
            Spacer(minLength: 8)
            if canAdd {
                Button(action: onAdd) {
                    Text("Добавить")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(OneCartPalette.primary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HomeEmptyListsPanel: View {
    let canEdit: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Пока пусто")
                .font(.headline)
            Text("Создайте список для магазина — семья сможет править его вместе с вами.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if canEdit {
                Button("Создать список", action: onCreate)
                    .font(.body.weight(.semibold))
                    .foregroundColor(OneCartPalette.primary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

private struct ShoppingListRow: View {
    let list: ShoppingListEntity
    let summary: ListOverviewSummary

    var body: some View {
        HStack(spacing: 14) {
            mark
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(list.store?.displayName ?? list.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(countLabel)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(summary.productCount == 0 ? Color.secondary.opacity(0.55) : Color.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mark: some View {
        if let store = list.store {
            StoreBrandMark(
                storeName: store.displayName,
                fallbackIcon: store.displayIcon,
                fallbackColorHex: store.displayColorHex,
                size: 48
            )
        } else {
            Image(systemName: "list.bullet")
                .font(.body.weight(.semibold))
                .foregroundColor(OneCartPalette.primaryStrong)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    OneCartPalette.primarySoft,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var subtitle: String {
        if let address = list.store?.address, !address.isEmpty {
            return address
        }
        if summary.productCount == 0 {
            return "Пустой список"
        }
        return "\(summary.productCount) тов."
    }

    private var countLabel: String {
        if summary.productCount == 0 {
            return "0"
        }
        return "\(summary.purchasedCount)/\(summary.productCount)"
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

    var body: some View {
        NavigationView {
            Form {
                Section("Список") {
                    TextField("Название", text: $title)
                    Picker("Магазин", selection: $selectedStoreID) {
                        Text("Без магазина").tag(UUID?.none)
                        ForEach(model.stores, id: \.objectID) { store in
                            Text(store.displayName).tag(store.id)
                        }
                    }
                    .onChange(of: selectedStoreID) { storeID in
                        if let store = model.stores.first(where: { $0.id == storeID }) {
                            title = "Покупки в \(store.displayName)"
                        } else {
                            title = "Список покупок"
                        }
                    }
                }
            }
            .navigationTitle("Новый список")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        let store = model.stores.first { $0.id == selectedStoreID }
                        Task {
                            await model.addList(title: title, store: store)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ShoppingListView: View {
    @EnvironmentObject private var model: AppModel
    let listID: UUID

    @State private var showingAddProduct = false
    @State private var showingOfficialCatalog = false
    @State private var editingProduct: ProductEntity?
    @State private var confirmingCompletion = false

    private var list: ShoppingListEntity? {
        model.lists.first { $0.id == listID }
    }

    private var products: [ProductEntity] {
        model.products(inListID: listID)
    }

    private var catalogBrand: StoreBrand? {
        guard let storeName = list?.store?.displayName else { return nil }
        return StoreBrand.matching(storeName)
    }

    var body: some View {
        Group {
            if let list {
                List {
                    if !model.canEdit {
                        Section {
                            ReadOnlyBanner()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        if products.isEmpty {
                            EmptyCard(
                                image: "cart.badge.plus",
                                title: "Список пуст",
                                message: catalogBrand == nil
                                    ? "Добавьте первый товар вручную."
                                    : "Откройте официальный каталог и добавьте товар вместе с фото и ценой."
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        } else {
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
                                    onMove: { destination in
                                        Task {
                                            await model.moveProduct(
                                                product,
                                                to: destination
                                            )
                                        }
                                    }
                                )
                                .listRowInsets(
                                    EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 10)
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await model.deleteProduct(product) }
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                    .disabled(!model.canEdit)
                                }
                            }
                        }
                    } header: {
                        Text("\(products.count) товаров")
                    }

                    if !products.isEmpty {
                        Section {
                            Button {
                                confirmingCompletion = true
                            } label: {
                                Label("Завершить покупку", systemImage: "checkmark.seal.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .foregroundColor(OneCartPalette.primary)
                            .disabled(!model.canEdit)
                        } footer: {
                            Text("Товары сохранятся в истории, а для магазина появится новый пустой список.")
                        }
                    }
                }
                .navigationTitle(list.store?.displayName ?? list.displayTitle)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            if catalogBrand == nil {
                                showingAddProduct = true
                            } else {
                                showingOfficialCatalog = true
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!model.canEdit)
                        .accessibilityLabel(
                            catalogBrand == nil ? "Добавить товар" : "Открыть каталог товаров"
                        )
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
            } else {
                ContentUnavailableViewCompat(
                    image: "questionmark.folder",
                    title: "Список недоступен",
                    message: "Он мог быть удалён или перемещён владельцем."
                )
            }
        }
    }
}

private struct ProductRow: View {
    let product: ProductEntity
    let lists: [ShoppingListEntity]
    let canEdit: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onMove: (ShoppingListEntity) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggle) {
                Image(
                    systemName: product.isPurchasedValue
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title3)
                .foregroundColor(
                    product.isPurchasedValue
                        ? OneCartPalette.primary
                        : Color.secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)

            OfficialProductThumbnail(
                media: OfficialProductMedia.resolve(product: product),
                category: product.categoryValue,
                isPurchased: product.isPurchasedValue
            )

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(product.isPurchasedValue)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if product.estimatedPriceValue > 0 {
                            Text(product.estimatedPriceValue.oneCartCurrency)
                                .font(.subheadline.bold())
                                .foregroundColor(
                                    product.originalPriceValue == nil ? .primary : .red
                                )
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(productSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let originalPrice = product.originalPriceValue {
                            Text(originalPrice.oneCartCurrency)
                                .strikethrough(true)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)

            Menu {
                if let sourceURL = product.sourceURLValue {
                    Link(destination: sourceURL) {
                        Label("Открыть официальный товар", systemImage: "safari")
                    }
                }

                ForEach(
                    lists.filter { $0.id != product.list?.id },
                    id: \.objectID
                ) { list in
                    Button(list.store?.displayName ?? list.displayTitle) {
                        onMove(list)
                    }
                    .disabled(!canEdit)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
            }
            .disabled(product.sourceURLValue == nil && (!canEdit || lists.count < 2))
        }
        .padding(.vertical, 1)
    }

    private var productSubtitle: String {
        var parts = [
            "\(product.quantityValue.oneCartQuantity) \(product.unitValue.localizedName)",
            product.categoryValue.localizedName,
        ]
        if let purchasedBy = product.purchasedByName, !purchasedBy.isEmpty {
            parts.append(purchasedBy)
        }
        return parts.joined(separator: " · ")
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
            initialValue: product.map { $0.quantityValue.oneCartQuantity } ?? "1"
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
                                size: 58
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Каталог \(media.sourceName)")
                                    .font(.subheadline.weight(.semibold))
                                Link("Открыть официальный товар", destination: media.sourceURL)
                                    .font(.caption)
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
            originalPrice: product?.originalPrice?.doubleValue
        )
        Task {
            if let product {
                await model.updateProduct(product, draft: draft)
            } else {
                await model.addProduct(to: list, draft: draft)
            }
            dismiss()
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
                Text("Товары останутся в семейном пространстве без привязки к магазину.")
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
            List {
                if model.history.isEmpty {
                    EmptyCard(
                        image: "clock",
                        title: "История пуста",
                        message: "Завершённые покупки появятся здесь."
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(model.history, id: \.objectID) { entry in
                        NavigationLink {
                            HistoryDetailView(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.store?.displayName ?? "Общий список")
                                        .font(.headline)
                                    Spacer()
                                    Text(entry.totalValue.oneCartCurrency)
                                        .font(.headline)
                                        .foregroundColor(OneCartPalette.primaryStrong)
                                }
                                Text(entry.purchaseDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(entry.sortedItems.count) товаров · \(entry.membersDisplay)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = entry
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            .disabled(!model.canEdit)
                        }
                    }
                }
            }
            .navigationTitle("История")
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

private struct HistoryDetailView: View {
    let entry: PurchaseHistoryEntity

    var body: some View {
        List {
            Section {
                LabeledContentCompat(
                    label: "Дата",
                    value: entry.purchaseDate.formatted(date: .long, time: .shortened)
                )
                LabeledContentCompat(label: "Участники", value: entry.membersDisplay)
                LabeledContentCompat(label: "Итого", value: entry.totalValue.oneCartCurrency)
            }

            Section("Товары") {
                ForEach(entry.sortedItems, id: \.objectID) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.body.weight(.semibold))
                            Text(
                                "\(item.quantityValue.oneCartQuantity) \(item.unitValue.localizedName)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.estimatedPriceValue.oneCartCurrency)
                    }
                }
            }
        }
        .navigationTitle(entry.store?.displayName ?? "Покупка")
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
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .oneCartCard()
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

struct LabeledContentCompat: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension Double {
    var oneCartCurrency: String {
        formatted(
            .currency(code: "UAH")
                .locale(Locale(identifier: "uk_UA"))
                .precision(.fractionLength(0...2))
        )
    }

    var oneCartQuantity: String {
        formatted(.number.precision(.fractionLength(0...2)))
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
