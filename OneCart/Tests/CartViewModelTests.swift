import Foundation
@testable import OneCart
import Testing

/// The cart ViewModel over value fakes: no Core Data store is involved.
@MainActor
struct CartHarness {
    let isolated: IsolatedPreferences
    let state: FakeSessionState
    let cart = FakeCartEditor()
    let history = FakeHistoryBrowser()
    let household = FakeHouseholdCartBootstrapper()
    let alerts = FakeAlertPresenter()
    let tabs = FakeMainTabRouter()
    let trip = FakeShoppingTripController()
    let viewModel: CartViewModel
    /// The general list the harness shows when it starts with lines.
    let list = CartList.general()

    /// `lines` in cart order (the session's order: newest to-buy first, then completed); `nil`
    /// leaves the session without any list.
    init(lines: [CartItem]? = nil) throws {
        isolated = try IsolatedPreferences()
        state = FakeSessionState(preferences: isolated.preferences)
        if let lines {
            state.cartLists = [list]
            state.itemsByListID[list.id] = lines
        }
        viewModel = CartViewModel(
            state: state,
            cart: cart,
            history: history,
            household: household,
            alerts: alerts,
            tabs: tabs,
            trip: trip,
            duplicateHighlightNanoseconds: 0
        )
    }

    /// Replaces the primary list's lines, as a session reload would.
    func show(_ lines: [CartItem]) {
        state.itemsByListID[list.id] = lines
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
        let milk = CartItem.line("Milk")
        let bread = CartItem.line("Bread")
        let soap = CartItem.line("Soap", purchased: true)
        let harness = try CartHarness(lines: [milk, bread, soap])
        let viewModel = harness.viewModel

        #expect(viewModel.primaryListID == harness.list.id)
        #expect(viewModel.totalCount == 3)
        #expect(viewModel.purchasedCount == 1)
        #expect(viewModel.toBuyProducts.map(\.id) == [milk.id, bread.id])
        #expect(viewModel.completedProducts.map(\.id) == [soap.id])
        #expect(!viewModel.isAllPurchased)
        #expect(!viewModel.isEmpty)

        let sectionedIDs = viewModel.toBuySections.flatMap(\.items).map(\.id)
        #expect(Set(sectionedIDs) == [bread.id, milk.id])
        for section in viewModel.toBuySections {
            #expect(section.items.allSatisfy { $0.category == section.category })
        }
    }

    @Test("REQ-CART-040: the cart counts as all purchased once every line is checked")
    func allPurchasedWhenEveryLineIsChecked() async throws {
        let harness = try CartHarness(lines: [.line("Bread", purchased: true)])

        #expect(harness.viewModel.isAllPurchased)
        #expect(harness.viewModel.toBuySections.isEmpty)
    }

    @Test("REQ-SHELL-010: the progress header follows the completed share and hides on an empty cart")
    func progressAccessoryTracksCompletedShare() async throws {
        let harness = try CartHarness(lines: [])
        harness.state.activeFamilySpace = try FamilySpace.detached()

        #expect(harness.viewModel.progressFraction == 0)
        #expect(!harness.viewModel.showsProgress)

        harness.show([.line("Bread"), .line("Milk", purchased: true)])

        #expect(harness.viewModel.showsProgress)
        #expect(harness.viewModel.progressFraction == 0.5)

        harness.state.activeFamilySpace = nil
        #expect(!harness.viewModel.showsProgress)
    }

    @Test("REQ-CART-030: adding a name-only item sends a trimmed draft to the primary list")
    func addItemSendsTrimmedDraft() async throws {
        let harness = try CartHarness(lines: [])
        let newID = UUID()
        harness.cart.addResult = newID

        let outcome = await harness.viewModel.addItem(named: "  Bread  ")

        #expect(outcome == .added(newID))
        let added = try #require(harness.cart.addedProducts.first)
        #expect(added.listID == harness.list.id)
        #expect(added.draft == ProductDraft(name: "Bread", category: ProductCategory.inferred(from: "Bread")))
        #expect(harness.viewModel.duplicateHighlightID == nil)
    }

    @Test("REQ-CART-030: blank names, read-only carts and rejected adds change nothing")
    func addItemRejectsBlankAndReadOnly() async throws {
        let harness = try CartHarness(lines: [])
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
        let bread = CartItem.line("Bread")
        let harness = try CartHarness(lines: [bread])
        harness.cart.addResult = bread.id

        let outcome = await harness.viewModel.addItem(named: "bread")

        #expect(outcome == .duplicate(bread.id))
        #expect(harness.viewModel.duplicateHighlightID == bread.id)
    }

    @Test("REQ-CART-090: the duplicate highlight clears after its delay")
    func duplicateHighlightClears() async throws {
        let bread = CartItem.line("Bread")
        let harness = try CartHarness(lines: [bread])
        harness.cart.addResult = bread.id

        _ = await harness.viewModel.addItem(named: "bread")
        for _ in 0..<1000 where harness.viewModel.duplicateHighlightID != nil {
            await Task.yield()
        }

        #expect(harness.viewModel.duplicateHighlightID == nil)
    }

    @Test("REQ-CART-040: checking the last to-buy item celebrates once until something is unchecked")
    func celebrationFiresOncePerCompletion() async throws {
        let bread = CartItem.line("Bread")
        let soap = CartItem.line("Soap", purchased: true)
        let harness = try CartHarness(lines: [bread, soap])

        await harness.viewModel.togglePurchased(bread, shownAsPurchased: false)
        #expect(harness.viewModel.confettiTrigger == 1)

        // The fake keeps the lines unchanged, so this is the same "last item" toggle again.
        await harness.viewModel.togglePurchased(bread, shownAsPurchased: false)
        #expect(harness.viewModel.confettiTrigger == 1)

        // Unchecking a completed line re-arms the celebration.
        await harness.viewModel.togglePurchased(soap, shownAsPurchased: true)
        await harness.viewModel.togglePurchased(bread, shownAsPurchased: false)
        #expect(harness.viewModel.confettiTrigger == 2)
        #expect(harness.cart.toggledProductIDs == [bread.id, bread.id, soap.id, bread.id])
        #expect(harness.cart.requestedPurchaseStates == [true, true, false, true])
    }

    @Test("REQ-CART-040: a tap asks for the opposite of the state the row was drawn with")
    func toggleRequestsTheOppositeOfTheShownState() async throws {
        let bread = CartItem.line("Bread")
        let harness = try CartHarness(lines: [bread, .line("Milk")])
        // Another shopper's check reached the session before the row was redrawn.
        harness.show([.line("Bread", purchased: true, id: bread.id), .line("Milk")])

        await harness.viewModel.togglePurchased(bread, shownAsPurchased: false)

        #expect(harness.cart.requestedPurchaseStates == [true])
        #expect(harness.cart.toggledProductIDs == [bread.id])
    }

    @Test("REQ-CART-040: checking an item while others remain does not celebrate")
    func noCelebrationWhileOthersRemain() async throws {
        let bread = CartItem.line("Bread")
        let harness = try CartHarness(lines: [bread, .line("Milk")])

        await harness.viewModel.togglePurchased(bread, shownAsPurchased: false)

        #expect(harness.viewModel.confettiTrigger == 0)
        #expect(harness.cart.toggledProductIDs == [bread.id])
    }

    @Test("REQ-CART-040: a read-only cart ignores toggles")
    func readOnlyCartIgnoresToggles() async throws {
        let bread = CartItem.line("Bread")
        let harness = try CartHarness(lines: [bread])
        harness.state.canEdit = false

        await harness.viewModel.togglePurchased(bread, shownAsPurchased: false)

        #expect(harness.cart.toggledProductIDs.isEmpty)
        #expect(harness.viewModel.confettiTrigger == 0)
    }

    @Test("REQ-CART-050: completed items are never deleted; to-buy items are")
    func deleteSkipsCompletedItems() async throws {
        let bread = CartItem.line("Bread")
        let soap = CartItem.line("Soap", purchased: true)
        let harness = try CartHarness(lines: [bread, soap])

        await harness.viewModel.deleteProduct(soap)
        #expect(harness.cart.deletedProductIDs.isEmpty)

        await harness.viewModel.deleteProduct(bread)
        #expect(harness.cart.deletedProductIDs == [bread.id])
    }

    @Test("REQ-CART-020: renaming a line sends only the trimmed name and its re-inferred category")
    func renameSendsOnlyTheNameAndInferredCategory() async throws {
        let bread = CartItem.line("Bread")
        let harness = try CartHarness(lines: [bread])

        #expect(await harness.viewModel.rename(bread, to: "  Milk "))

        let update = try #require(harness.cart.updatedProducts.first)
        #expect(update.id == bread.id)
        #expect(update.draft == ProductDraft(name: "Milk", category: ProductCategory.inferred(from: "Milk")))
    }

    @Test("REQ-CART-020: an unchanged or blank name saves nothing")
    func renameIgnoresUnchangedAndBlankNames() async throws {
        let bread = CartItem.line("Bread")
        let harness = try CartHarness(lines: [bread])

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
        let owner = FamilyMember(
            id: UUID(),
            displayName: "Alex",
            access: .owner,
            joinedAt: Date(),
            isCurrentUser: true,
            avatarURL: nil,
            bannerURL: nil
        )
        harness.state.familyMembers = [owner]

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
        let harness = try CartHarness()
        let storeList = CartList.store(createdAt: Date(timeIntervalSince1970: 1000))
        let laterStoreList = CartList.store(createdAt: Date(timeIntervalSince1970: 2000))
        let general = CartList.general(createdAt: Date(timeIntervalSince1970: 3000))

        harness.state.cartLists = [laterStoreList, storeList, general]
        #expect(harness.viewModel.primaryListID == general.id)

        harness.state.cartLists = [laterStoreList, storeList]
        #expect(harness.viewModel.primaryListID == storeList.id)

        harness.state.cartLists = []
        #expect(harness.viewModel.primaryListID == nil)
        #expect(harness.viewModel.products.isEmpty)
    }

    @Test("REQ-CART-090: suggestions never repeat a name already on the cart")
    func suggestionsExcludeCartLines() async throws {
        // The essentials follow the device language, so the cart line is taken from that list.
        let onCart = try #require(CartSuggestionsEngine.defaultEssentials().first)
        let harness = try CartHarness(lines: [.line(onCart)])

        let suggestions = harness.viewModel.suggestions(matching: "")

        #expect(!suggestions.isEmpty)
        #expect(!suggestions.contains { $0.localizedCaseInsensitiveCompare(onCart) == .orderedSame })
    }
}
