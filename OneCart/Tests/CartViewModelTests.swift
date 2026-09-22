import CoreData
import Foundation
@testable import OneCart
import Testing

@MainActor
struct CartHarness {
    let isolated: IsolatedPreferences
    let state: FakeSessionState
    let cart = FakeCartEditor()
    let history = FakeHistoryBrowser()
    let household = FakeHouseholdCartBootstrapper()
    let alerts = FakeAlertPresenter()
    let tabs = FakeMainTabRouter()
    let viewModel: CartViewModel

    init(fixture: CartFixture? = nil) throws {
        isolated = try IsolatedPreferences()
        state = FakeSessionState(preferences: isolated.preferences)
        if let fixture {
            state.activeLists = try [fixture.list]
            state.productsByListID[fixture.listID] = try fixture.products
        }
        viewModel = CartViewModel(
            state: state,
            cart: cart,
            history: history,
            household: household,
            alerts: alerts,
            tabs: tabs,
            duplicateHighlightNanoseconds: 0
        )
    }
}

@MainActor
@Suite("CartViewModelTests")
struct CartViewModelTests {
    @Test("REQ-CART-070: household bootstrap and its retry forward to the session")
    func householdBootstrapForwards() async throws {
        let harness = try CartHarness()
        #expect(!harness.viewModel.hasActiveFamilySpace)
        #expect(harness.viewModel.householdBootstrapTaskID == "no-account")

        await harness.viewModel.ensureHouseholdCartIfNeeded()
        harness.household.householdCartBootstrapFailed = true
        await harness.viewModel.retryHouseholdCartBootstrap()

        #expect(harness.household.ensureCount == 1)
        #expect(harness.household.retryCount == 1)
        #expect(harness.viewModel.householdCartBootstrapFailed)

        let account = OneCartAccount(id: UUID(), displayName: "Alex")
        harness.state.account = account
        #expect(harness.viewModel.householdBootstrapTaskID == account.id.uuidString)
    }

    @Test("REQ-SHELL-010: to-buy lines group by category while completed lines stay flat")
    func toBuyGroupsByCategoryAndCompletedStaysFlat() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let milkID = try await fixture.addProduct(named: "Milk")
        let soapID = try await fixture.addProduct(named: "Soap", purchased: true)
        let harness = try CartHarness(fixture: fixture)
        let viewModel = harness.viewModel

        #expect(viewModel.primaryListID == fixture.listID)
        #expect(viewModel.totalCount == 3)
        #expect(viewModel.purchasedCount == 1)
        #expect(Set(viewModel.toBuyProducts.compactMap(\.id)) == [breadID, milkID])
        #expect(viewModel.completedProducts.compactMap(\.id) == [soapID])
        #expect(!viewModel.isAllPurchased)
        #expect(!viewModel.isEmpty)

        let sectionedIDs = viewModel.toBuySections.flatMap(\.items).compactMap(\.id)
        #expect(Set(sectionedIDs) == [breadID, milkID])
        for section in viewModel.toBuySections {
            #expect(section.items.allSatisfy { $0.categoryValue == section.category })
        }
    }

    @Test("REQ-CART-040: the cart counts as all purchased once every line is checked")
    func allPurchasedWhenEveryLineIsChecked() async throws {
        let fixture = try await CartFixture.make()
        try await fixture.addProduct(named: "Bread", purchased: true)
        let harness = try CartHarness(fixture: fixture)

        #expect(harness.viewModel.isAllPurchased)
        #expect(harness.viewModel.toBuySections.isEmpty)
    }

    @Test("REQ-CART-030: adding a name-only item sends a trimmed draft to the primary list")
    func addItemSendsTrimmedDraft() async throws {
        let fixture = try await CartFixture.make()
        let harness = try CartHarness(fixture: fixture)
        let newID = UUID()
        harness.cart.addResult = newID

        let outcome = await harness.viewModel.addItem(named: "  Bread  ")

        #expect(outcome == .added(newID))
        let added = try #require(harness.cart.addedProducts.first)
        #expect(added.listID == fixture.listID)
        #expect(added.draft.name == "Bread")
        #expect(added.draft.quantity == 1)
        #expect(added.draft.unit == .piece)
        #expect(added.draft.category == ProductCategory.inferred(from: "Bread"))
        #expect(added.draft.note.isEmpty)
        #expect(harness.viewModel.duplicateHighlightID == nil)
    }

    @Test("REQ-CART-030: blank names, read-only carts and rejected adds change nothing")
    func addItemRejectsBlankAndReadOnly() async throws {
        let fixture = try await CartFixture.make()
        let harness = try CartHarness(fixture: fixture)
        harness.cart.addResult = UUID()

        #expect(await harness.viewModel.addItem(named: "   ") == .rejected)
        harness.state.canEdit = false
        #expect(await harness.viewModel.addItem(named: "Bread") == .rejected)
        #expect(harness.cart.addedProducts.isEmpty)

        harness.state.canEdit = true
        harness.cart.addResult = nil
        #expect(await harness.viewModel.addItem(named: "Bread") == .rejected)
        #expect(harness.cart.addedProducts.count == 1)
    }

    @Test("REQ-CART-090: adding a name already on the cart highlights the existing line")
    func addItemReportsDuplicate() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let harness = try CartHarness(fixture: fixture)
        harness.cart.addResult = breadID

        let outcome = await harness.viewModel.addItem(named: "bread")

        #expect(outcome == .duplicate(breadID))
        #expect(harness.viewModel.duplicateHighlightID == breadID)
    }

    @Test("REQ-CART-040: checking the last to-buy item celebrates once until something is unchecked")
    func celebrationFiresOncePerCompletion() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let soapID = try await fixture.addProduct(named: "Soap", purchased: true)
        let harness = try CartHarness(fixture: fixture)
        let bread = try fixture.product(id: breadID)
        let soap = try fixture.product(id: soapID)

        await harness.viewModel.togglePurchased(bread)
        #expect(harness.viewModel.confettiTrigger == 1)

        // The fake keeps the entity unchanged, so this is the same "last item" toggle again.
        await harness.viewModel.togglePurchased(bread)
        #expect(harness.viewModel.confettiTrigger == 1)

        // Unchecking a completed line re-arms the celebration.
        await harness.viewModel.togglePurchased(soap)
        await harness.viewModel.togglePurchased(bread)
        #expect(harness.viewModel.confettiTrigger == 2)
        #expect(harness.cart.toggledProducts.count == 4)
    }

    @Test("REQ-CART-040: checking an item while others remain does not celebrate")
    func noCelebrationWhileOthersRemain() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        try await fixture.addProduct(named: "Milk")
        let harness = try CartHarness(fixture: fixture)

        try await harness.viewModel.togglePurchased(fixture.product(id: breadID))

        #expect(harness.viewModel.confettiTrigger == 0)
        #expect(harness.cart.toggledProducts.compactMap(\.id) == [breadID])
    }

    @Test("REQ-CART-040: a read-only cart ignores toggles")
    func readOnlyCartIgnoresToggles() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let harness = try CartHarness(fixture: fixture)
        harness.state.canEdit = false

        try await harness.viewModel.togglePurchased(fixture.product(id: breadID))

        #expect(harness.cart.toggledProducts.isEmpty)
        #expect(harness.viewModel.confettiTrigger == 0)
    }

    @Test("REQ-CART-050: completed items are never deleted; to-buy items are")
    func deleteSkipsCompletedItems() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let soapID = try await fixture.addProduct(named: "Soap", purchased: true)
        let harness = try CartHarness(fixture: fixture)

        try await harness.viewModel.deleteProduct(fixture.product(id: soapID))
        #expect(harness.cart.deletedProducts.isEmpty)

        try await harness.viewModel.deleteProduct(fixture.product(id: breadID))
        #expect(harness.cart.deletedProducts.compactMap(\.id) == [breadID])
    }

    @Test("REQ-CART-020: renaming a line keeps its other fields and re-infers the category")
    func renameKeepsFieldsAndInfersCategory() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let harness = try CartHarness(fixture: fixture)
        let bread = try fixture.product(id: breadID)

        #expect(await harness.viewModel.rename(bread, to: "  Milk "))

        let update = try #require(harness.cart.updatedProducts.first)
        #expect(update.product.id == breadID)
        #expect(update.draft.name == "Milk")
        #expect(update.draft.quantity == bread.quantityValue)
        #expect(update.draft.unit == bread.unitValue)
        #expect(update.draft.note == bread.noteValue)
        #expect(update.draft.category == ProductCategory.inferred(from: "Milk"))
    }

    @Test("REQ-CART-020: an unchanged or blank name saves nothing")
    func renameIgnoresUnchangedAndBlankNames() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let harness = try CartHarness(fixture: fixture)
        let bread = try fixture.product(id: breadID)

        #expect(await !harness.viewModel.rename(bread, to: "Bread"))
        #expect(await !harness.viewModel.rename(bread, to: "   "))
        harness.state.canEdit = false
        #expect(await !harness.viewModel.rename(bread, to: "Milk"))
        #expect(harness.cart.updatedProducts.isEmpty)
    }

    @Test("REQ-SHELL-010: pull-to-refresh, family management and the removed-cart notice forward")
    func chromeActionsForward() async throws {
        let harness = try CartHarness()
        harness.alerts.sharedCartRemovedMessage = "The shared cart is gone"
        harness.state.familyMembers = [
            FamilyMember(
                id: UUID(),
                displayName: "Alex",
                access: .owner,
                joinedAt: Date(),
                isCurrentUser: true,
                avatarURL: nil,
                bannerURL: nil
            ),
        ]

        #expect(harness.viewModel.sharedCartRemovedMessage == "The shared cart is gone")
        #expect(harness.viewModel.familyMembersCount == 1)

        await harness.viewModel.sync(reason: .pull)
        await harness.viewModel.sync(reason: .appear)
        harness.viewModel.showFamilyManagement()
        harness.viewModel.dismissSharedCartRemovedMessage()

        #expect(harness.cart.syncReasons == [.pull, .appear])
        #expect(harness.tabs.showFamilyManagementCount == 1)
        #expect(harness.tabs.preferredMainTab == .account)
        #expect(harness.alerts.dismissSharedCartRemovedMessageCount == 1)
        #expect(harness.viewModel.sharedCartRemovedMessage == nil)
    }

    @Test("REQ-CART-010: the primary list is the general one, else the oldest active list")
    func primaryListPrefersGeneralThenOldest() async throws {
        let fixture = try await CartFixture.make()
        let harness = try CartHarness()
        let context = fixture.persistence.container.viewContext
        let store = StoreEntity(context: context)
        let storeList = ShoppingListEntity(context: context)
        storeList.id = UUID()
        storeList.store = store
        storeList.createdAt = Date(timeIntervalSince1970: 1000)
        let laterStoreList = ShoppingListEntity(context: context)
        laterStoreList.id = UUID()
        laterStoreList.store = store
        laterStoreList.createdAt = Date(timeIntervalSince1970: 2000)
        let general = try fixture.list

        harness.state.activeLists = [laterStoreList, storeList, general]
        #expect(harness.viewModel.primaryListID == general.id)

        harness.state.activeLists = [laterStoreList, storeList]
        #expect(harness.viewModel.primaryListID == storeList.id)

        harness.state.activeLists = []
        #expect(harness.viewModel.primaryListID == nil)
        #expect(harness.viewModel.products.isEmpty)
    }

    @Test("REQ-CART-090: suggestions never repeat a name already on the cart")
    func suggestionsExcludeCartLines() async throws {
        let fixture = try await CartFixture.make()
        try await fixture.addProduct(named: "Молоко")
        let harness = try CartHarness(fixture: fixture)
        harness.isolated.preferences.language = .russian

        let suggestions = harness.viewModel.suggestions(matching: "")

        #expect(!suggestions.isEmpty)
        #expect(!suggestions.contains { $0.localizedCaseInsensitiveCompare("Молоко") == .orderedSame })
    }
}
