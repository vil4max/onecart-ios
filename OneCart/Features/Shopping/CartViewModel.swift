import Foundation

/// Everything the cart screen needs from the session; the composition root satisfies `init(session:)` with one object.
typealias CartSessionServices = AlertPresenting & CartEditing & HistoryBrowsing
    & HouseholdCartBootstrapping & MainTabRouting & SessionStateReading & ShoppingTripControlling

/// The living cart: household bootstrap, the primary list's lines and their mutations.
@MainActor
@Observable
final class CartViewModel {
    enum AddOutcome: Equatable {
        case added(UUID)
        /// The name already lives on the cart; the existing line is highlighted instead (REQ-CART-090).
        case duplicate(UUID)
        case rejected
    }

    /// Increments when the shopper checks off the last to-buy item; the view keys confetti on it.
    private(set) var confettiTrigger = 0
    /// Existing line to flash after an add resolved to it; cleared after `duplicateHighlightNanoseconds`.
    private(set) var duplicateHighlightID: UUID?
    private var hasCelebratedCurrentCompletion = false

    private let state: any SessionStateReading
    private let cart: any CartEditing
    private let historyBrowser: any HistoryBrowsing
    private let household: any HouseholdCartBootstrapping
    private let alerts: any AlertPresenting
    private let tabs: any MainTabRouting
    private let trip: any ShoppingTripControlling
    private let duplicateHighlightNanoseconds: UInt64

    init(
        state: any SessionStateReading,
        cart: any CartEditing,
        history: any HistoryBrowsing,
        household: any HouseholdCartBootstrapping,
        alerts: any AlertPresenting,
        tabs: any MainTabRouting,
        trip: any ShoppingTripControlling,
        duplicateHighlightNanoseconds: UInt64 = 1_800_000_000
    ) {
        self.state = state
        self.cart = cart
        historyBrowser = history
        self.household = household
        self.alerts = alerts
        self.tabs = tabs
        self.trip = trip
        self.duplicateHighlightNanoseconds = duplicateHighlightNanoseconds
    }

    convenience init(session: any CartSessionServices) {
        self.init(
            state: session,
            cart: session,
            history: session,
            household: session,
            alerts: session,
            tabs: session,
            trip: session
        )
    }

    // MARK: - Household bootstrap

    var hasActiveFamilySpace: Bool {
        state.activeFamilySpace != nil
    }

    var householdCartBootstrapFailed: Bool {
        household.householdCartBootstrapFailed
    }

    /// Restarts the bootstrap task when the signed-in account changes.
    var householdBootstrapTaskID: String {
        state.account?.id.uuidString ?? "no-account"
    }

    func ensureHouseholdCartIfNeeded() async {
        await household.ensureHouseholdCartIfNeeded()
    }

    func retryHouseholdCartBootstrap() async {
        await household.retryHouseholdCartBootstrap()
    }

    // MARK: - Chrome

    var cartTitle: String {
        state.cartTitle
    }

    var canEdit: Bool {
        state.canEdit
    }

    var isBusy: Bool {
        state.isBusy
    }

    var isCartSyncing: Bool {
        state.isCartSyncing
    }

    var contentRevision: Int {
        state.contentRevision
    }

    var familyMembersCount: Int {
        state.familyMembers.count
    }

    var accentColor: AppAccentColor {
        state.preferences.accentColor
    }

    var sharedCartRemovedMessage: String? {
        alerts.sharedCartRemovedMessage
    }

    func dismissSharedCartRemovedMessage() {
        alerts.dismissSharedCartRemovedMessage()
    }

    func showFamilyManagement() {
        tabs.showFamilyManagement()
    }

    func sync(reason: CartSyncReason) async {
        await cart.syncCart(reason: reason)
    }

    // MARK: - Content

    /// Stable household cart list: prefer the general (no-store) list, else the oldest active.
    var primaryList: ShoppingListEntity? {
        Self.primaryList(in: state.activeLists)
    }

    /// Shared with Siri, so an item said aloud lands on the list the cart screen shows.
    static func primaryList(in lists: [ShoppingListEntity]) -> ShoppingListEntity? {
        if let general = lists.first(where: { $0.store == nil }) {
            return general
        }
        return lists.min { lhs, rhs in
            (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
        }
    }

    var primaryListID: UUID? {
        primaryList?.id
    }

    var products: [ProductEntity] {
        guard let listID = primaryListID else { return [] }
        return state.products(inListID: listID)
    }

    var toBuyProducts: [ProductEntity] {
        products.filter { !$0.isPurchasedValue }
    }

    var toBuySections: [(category: ProductCategory, items: [ProductEntity])] {
        ProductCategory.groupedSections(from: toBuyProducts) { $0.categoryValue }
    }

    var completedProducts: [ProductEntity] {
        products.filter(\.isPurchasedValue)
    }

    var totalCount: Int {
        products.count
    }

    var purchasedCount: Int {
        completedProducts.count
    }

    var isEmpty: Bool {
        products.isEmpty
    }

    var isAllPurchased: Bool {
        CartCelebration.isAllPurchased(totalCount: totalCount, toBuyCount: toBuyProducts.count)
    }

    /// Completed share of the cart for the progress bar; an empty cart reads as no progress.
    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(purchasedCount) / Double(totalCount)
    }

    /// The progress header tracks the trip only while the living cart has lines on it.
    var showsProgress: Bool {
        hasActiveFamilySpace && !isEmpty
    }

    // MARK: - Shopping trip

    var isShoppingTripActive: Bool {
        trip.isShoppingTripActive
    }

    /// A running trip can always be stopped; a new one needs an editable cart with lines
    /// still to buy and Live Activities allowed (REQ-WIDGET-040).
    var showsShoppingTripControl: Bool {
        isShoppingTripActive || (canEdit && !toBuyProducts.isEmpty && trip.areShoppingTripsAvailable)
    }

    func toggleShoppingTrip() async {
        if isShoppingTripActive {
            await trip.endShoppingTrip()
        } else {
            await trip.startShoppingTrip()
        }
    }

    func suggestions(matching query: String) -> [String] {
        CartSuggestionsEngine.suggestions(
            from: historyBrowser.history,
            currentCartProducts: products,
            query: query,
            defaults: CartSuggestionsEngine.defaultEssentials(
                languageCode: state.preferences.language.languageCode
            )
        )
    }

    // MARK: - Actions

    func addItem(named rawName: String) async -> AddOutcome {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !name.isEmpty, let list = primaryList else { return .rejected }
        let existingIDs = Set(products.compactMap(\.id))
        guard let productID = await cart.addProduct(to: list, draft: .nameOnly(name)) else { return .rejected }
        if existingIDs.contains(productID) {
            flashDuplicateRow(productID)
            return .duplicate(productID)
        }
        hasCelebratedCurrentCompletion = false
        return .added(productID)
    }

    /// Renames a line, keeping every other field; returns false when nothing was saved.
    func rename(_ product: ProductEntity, to rawName: String) async -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !name.isEmpty, name != product.displayName else { return false }
        let draft = ProductDraft(
            name: name,
            quantity: product.quantityValue,
            unit: product.unitValue,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: product.estimatedPriceValue,
            note: product.noteValue,
            imageURL: product.imageURL,
            sourceURL: product.sourceURL,
            originalPrice: product.originalPrice?.doubleValue,
            loyaltyPrice: product.loyaltyPrice?.doubleValue,
            catalogFetchedAt: product.catalogFetchedAt,
            promotionEndsAt: product.promotionEndsAt
        )
        await cart.updateProduct(product, draft: draft)
        return true
    }

    func togglePurchased(_ product: ProductEntity) async {
        guard canEdit else { return }
        let willCompleteCart = CartCelebration.willCompleteCart(
            togglingPurchasedItem: product.isPurchasedValue,
            toBuyCount: toBuyProducts.count
        )
        if willCompleteCart, !hasCelebratedCurrentCompletion {
            hasCelebratedCurrentCompletion = true
            confettiTrigger += 1
        }
        if product.isPurchasedValue {
            hasCelebratedCurrentCompletion = false
        }
        await cart.togglePurchased(product)
    }

    /// Completed items cannot be deleted; uncheck first (REQ-CART-050).
    func deleteProduct(_ product: ProductEntity) async {
        guard canEdit, !product.isPurchasedValue else { return }
        await cart.deleteProduct(product)
    }

    private func flashDuplicateRow(_ productID: UUID) {
        duplicateHighlightID = productID
        let delay = duplicateHighlightNanoseconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, duplicateHighlightID == productID else { return }
            duplicateHighlightID = nil
        }
    }
}

extension ProductDraft {
    /// A name-only line (REQ-CART-030, REQ-CART-060): no price, one piece, inferred category.
    static func nameOnly(_ name: String) -> ProductDraft {
        ProductDraft(
            name: name,
            quantity: 1,
            unit: .piece,
            category: ProductCategory.inferred(from: name),
            estimatedPrice: 0,
            note: ""
        )
    }
}

// MARK: - Cart celebration

/// Pure completion rules behind the confetti and the "all purchased" state,
/// kept out of the view so tests exercise the production conditions.
enum CartCelebration {
    static func isAllPurchased(totalCount: Int, toBuyCount: Int) -> Bool {
        totalCount > 0 && toBuyCount == 0
    }

    /// True when the toggle checks off the last remaining to-buy item.
    static func willCompleteCart(togglingPurchasedItem isPurchased: Bool, toBuyCount: Int) -> Bool {
        !isPurchased && toBuyCount == 1
    }
}
