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
                        .navigationTitle(String(localized: "cart.default_title"))
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
                            ?? String(localized: "cart.default_title")
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


struct ShoppingListView: View {
    @EnvironmentObject private var model: AppModel
    let listID: UUID

    // Share uses AppSession directly; ViewModel kept for members sheet only.
    @State private var showingAddProduct = false
    @State private var editingProduct: ProductEntity?
    @State private var confirmingCompletion = false
    @State private var pendingDelete: ProductEntity?
    @State private var sharePayload: CartSharePayload?
    @State private var isSharing = false
    @State private var shareAlert: String?
    @State private var showingProfile = false
    @State private var showingHistory = false

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

    var body: some View {
        Group {
            if let list {
                ZStack(alignment: .bottom) {
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
                                    message: String(localized: "home.empty_hint")
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
                                Button {
                                    confirmingCompletion = true
                                } label: {
                                    Label("Завершить", systemImage: "checkmark.seal.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(OneCartPrimaryButtonStyle())
                                .disabled(!model.canEdit)
                                .opacity(model.canEdit ? 1 : 0.5)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, model.canEdit ? 120 : 28)
                    }
                    .background(OneCartPalette.background.ignoresSafeArea())

                    bottomBar
                }
                .navigationTitle(
                    model.activeFamilySpace?.displayName
                        ?? String(localized: "cart.default_title")
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                model.showFamilyManagement()
                            } label: {
                                Label("Участники", systemImage: "person.2")
                            }
                            Button {
                                showingHistory = true
                            } label: {
                                Label("История", systemImage: "clock")
                            }
                            Button {
                                showingProfile = true
                            } label: {
                                Label("Профиль", systemImage: "person.crop.circle")
                            }
                            Divider()
                            Button(role: .destructive) {
                                model.signOut()
                            } label: {
                                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Ещё")
                    }
                }
                .sheet(isPresented: $showingAddProduct) {
                    QuickAddProductSheet(listID: listID)
                }
                .sheet(item: $editingProduct) { product in
                    QuickAddProductSheet(listID: listID, product: product)
                }
                .sheet(item: $sharePayload) { payload in
                    CartActivityViewController(
                        activityItems: [CartInviteActivityItem(link: payload.link)]
                    )
                }
                .sheet(isPresented: $showingHistory) {
                    HistoryView()
                        .environmentObject(model)
                }
                .sheet(isPresented: $showingProfile) {
                    if let account = model.account {
                        ProfileEditorSheet(
                            account: account,
                            avatar: model.profileAvatar,
                            banner: model.profileBanner
                        )
                    }
                }
                .alert(
                    "OneCart",
                    isPresented: Binding(
                        get: { shareAlert != nil },
                        set: { if !$0 { shareAlert = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { shareAlert = nil }
                } message: {
                    Text(shareAlert ?? "")
                }
                .alert("Завершить покупку?", isPresented: $confirmingCompletion) {
                    Button("Отмена", role: .cancel) {}
                    Button("Завершить") {
                        Task { await model.completePurchasedItems(list) }
                    }
                } message: {
                    Text("Отмеченные товары перейдут в историю.")
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
                    Text(pendingDelete?.displayName ?? "Товар будет удалён.")
                }

            } else {
                ContentUnavailableViewCompat(
                    image: "questionmark.folder",
                    title: "Список недоступен",
                    message: "Он мог быть удалён или перемещён."
                )
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if model.access?.isOwner == true {
                Button {
                    shareCart()
                } label: {
                    HStack(spacing: 8) {
                        if isSharing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Поделиться")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundColor(.white)
                    .background(
                        OneCartPalette.primary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .disabled(isSharing || !model.isOnline)
                .opacity(model.isOnline ? 1 : 0.55)
            }

            if model.canEdit {
                Button {
                    showingAddProduct = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(model.access?.isOwner == true ? OneCartPalette.primaryStrong : .white)
                        .frame(width: 56, height: 56)
                        .background(
                            model.access?.isOwner == true
                                ? OneCartPalette.primarySoft
                                : OneCartPalette.primary,
                            in: Circle()
                        )
                }
                .accessibilityLabel("Добавить товар")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func shareCart() {
        guard !isSharing else { return }
        isSharing = true
        let work = Task { @MainActor in
            defer { isSharing = false }
            do {
                let link: FamilyInviteLink
                if let cached = model.preparedInviteLink,
                   cached.expiresAt > Date().addingTimeInterval(30)
                {
                    link = cached
                } else {
                    link = try await model.createFamilyInviteLink()
                }
                guard !Task.isCancelled else { return }
                sharePayload = CartSharePayload(link: link)
            } catch is CancellationError {
                return
            } catch {
                shareAlert = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 24_000_000_000)
            guard !work.isCancelled else { return }
            if isSharing {
                work.cancel()
                isSharing = false
                shareAlert = OneCartCloudKitError.shareTimedOut.errorDescription
            }
        }
    }

    private var listSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("В корзине")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if products.isEmpty {
                    Text("Пока пусто")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(purchasedCount) из \(products.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !products.isEmpty {
                ProgressView(
                    value: Double(purchasedCount),
                    total: Double(products.count)
                )
                .tint(OneCartPalette.primary)
            } else if model.access?.isOwner == true {
                Text("Нажмите «Поделиться», чтобы пригласить семью в эту корзину.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel(isPurchased ? "Отметить как не купленное" : "Отметить как купленное")
        .accessibilityAddTraits(isPurchased ? [.isSelected] : [])
    }
}

private struct ProductRow: View {
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
                    Label("Изменить", systemImage: "pencil")
                }
                .disabled(!canEdit)

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
        product.isPurchasedValue ? "Куплено" : ""
    }
}

/// Minimal add/rename: product name only. Quantity/unit/category use defaults.

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
        NavigationView {
            VStack(spacing: 16) {
                TextField("Что купить?", text: $name)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        OneCartPalette.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .focused($nameFocused)
                    .submitLabel(isEditing ? .done : .next)
                    .onSubmit { save() }
                    .disabled(isSaving)

                Button {
                    save()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text(isEditing ? "Сохранить" : "Добавить")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(OneCartPrimaryButtonStyle())
                .disabled(trimmedName.isEmpty || isSaving)

                if !isEditing {
                    Text("После добавления можно сразу ввести следующий товар.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Изменить" : "Добавить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                nameFocused = true
            }
        }
        .navigationViewStyle(.stack)
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
                name = ""
                nameFocused = true
            }
        }
    }
}

/// Kept for any remaining call sites; forwards to the quick name editor.

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
                Image(systemName: "cart.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(OneCartPalette.primaryStrong)
                    .frame(width: 48, height: 48)
                    .background(
                        OneCartPalette.primarySoft,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Корзина")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(entry.sortedItems.count) товаров · \(entry.membersDisplay)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
                        Text("Дата")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(entry.purchaseDate.formatted(date: .long, time: .shortened))
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
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
        .navigationTitle("Корзина")
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
