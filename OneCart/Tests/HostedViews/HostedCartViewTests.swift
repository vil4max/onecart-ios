import CoreData
import Foundation
@testable import OneCart
import SwiftUI
import Testing

/// The cart hosted over the ViewModel fakes: bootstrap states, sections, the composer, and the
/// negative constraints that the screen carries no price and no share control.
@MainActor
@Suite("HostedCartViewTests")
struct HostedCartViewTests {
    /// Currency symbols and the word "price" in the app's languages; none may appear on the cart.
    private static let priceMarkers = ["$", "€", "₽", "₴", "price", "цена", "ціна"]

    private static func cartWithLines(purchased: Bool = false) async throws -> (CartFixture, CartHarness) {
        let fixture = try await CartFixture.make()
        _ = try await fixture.addProduct(named: "Milk", purchased: purchased)
        _ = try await fixture.addProduct(named: "Apple", purchased: purchased)
        _ = try await fixture.addProduct(named: "Bread", purchased: true)
        let harness = try CartHarness(fixture: fixture)
        harness.state.activeFamilySpace = try fixture.family
        harness.state.cartTitle = "Family"
        return (fixture, harness)
    }

    @Test("REQ-CART-070: the cart bootstraps the household on appear and offers retry after a failure")
    func bootstrapStatesRender() async throws {
        let harness = try CartHarness()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }

        #expect(hosted.element(identifier: "home.connecting")?.label?
            .contains(String(localized: "home.connecting_cart")) == true)
        #expect(await hosted.pump { harness.household.ensureCount == 1 })
        #expect(hosted.element(identifier: "home.retry") == nil)

        harness.household.householdCartBootstrapFailed = true
        #expect(await hosted.pump { hosted.element(identifier: "home.retry") != nil })
        #expect(hosted.containsLabel(String(localized: "home.connect_failed_title")))
        let retry = try #require(hosted.element(identifier: "home.retry"))
        #expect(retry.activate())
        #expect(await hosted.pump { harness.household.retryCount == 1 })
    }

    @Test("REQ-SHELL-010: to-buy lines sit in category sections, completed lines in one flat section, and appear syncs")
    func sectionsByCategoryAndCompletedFlat() async throws {
        let (_, harness) = try await Self.cartWithLines()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        // A row's label combines the name with its category and completion captions.
        let rows = hosted.elements(identifier: "cart.product_name").compactMap(\.label)
        let names = rows.map { $0.components(separatedBy: ", ").first ?? $0 }
        #expect(names == ["Milk", "Apple", "Bread"])
        #expect(rows.last?.contains(String(localized: "common.category.bakery")) == true)
        #expect(rows.last?.contains(String(localized: "cart.in_trolley_by \("Alex")")) == true)
        #expect(hosted.containsLabel(String(localized: "common.category.dairyEggs")))
        #expect(hosted.containsLabel(String(localized: "common.category.produce")))
        #expect(hosted.containsLabel(String(localized: "cart.section_in_trolley")))
        #expect(hosted.containsLabel(String(localized: "cart.trolley_history_hint")))
        #expect(hosted.elements(identifier: "cart.product_toggle").count == 3)
        #expect(hosted.elements(identifier: "cart.product_toggle").last?.isSelected == true)
        #expect(hosted.uiLabelTexts.contains("Family"))
        #expect(await hosted.pump { harness.cart.syncReasons == [.appear] })

        let members = try #require(hosted.element(identifier: "cart.members"))
        #expect(members.label == String(localized: "cart.members_a11y \(0)"))
        #expect(members.activate())
        #expect(await hosted.pump { harness.tabs.showFamilyManagementCount == 1 })
    }

    @Test("REQ-CART-060: the cart and its composer show no price, and REQ-SHELL-040: no share control")
    func noPriceAndNoShareOnCart() async throws {
        let (_, harness) = try await Self.cartWithLines()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        let add = try #require(hosted.element(identifier: "cart.add"))
        #expect(add.activate())
        #expect(await hosted.pump { hosted.element(identifier: "cart.add_field") != nil })

        for marker in Self.priceMarkers {
            #expect(!hosted.containsText(marker), "\(marker) is on the cart screen")
        }
        #expect(!hosted.identifiers.contains { $0.localizedCaseInsensitiveContains("price") })
        // The composer's name field is the only text entry on the screen.
        #expect(hosted.elements(identifier: "cart.add_field").count == 1)
        #expect(hosted.element(identifier: "cart.add_field")?.label == String(localized: "cart.add_a11y"))

        #expect(!hosted.containsLabel(String(localized: "account.share_cart")))
        #expect(!hosted.identifiers.contains { $0.localizedCaseInsensitiveContains("share") })
        // The one route out of the cart is the members button to Settings.
        #expect(hosted.buttons.filter { $0.identifier == "cart.members" }.count == 1)
    }

    @Test("REQ-CART-030: the composer opens from the add button, adds a name-only suggestion and closes")
    func composerAddsSuggestionAndCloses() async throws {
        let (_, harness) = try await Self.cartWithLines()
        harness.cart.addResult = UUID()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }

        #expect(hosted.element(identifier: "cart.add")?.label == String(localized: "cart.add_a11y"))
        #expect(hosted.element(identifier: "cart.add")?.activate() == true)
        #expect(await hosted.pump { hosted.element(identifier: "cart.add_field") != nil })
        #expect(hosted.element(identifier: "cart.add") == nil)

        let chips = hosted.elements(identifier: "cart.suggestion")
        let chip = try #require(chips.first)
        #expect(chip.activate())
        #expect(await hosted.pump { harness.cart.addedProducts.count == 1 })
        let added = try #require(harness.cart.addedProducts.first)
        #expect(chip.label == String(localized: "cart.suggestion_chip_a11y \(added.draft.name)"))
        #expect(added.draft.estimatedPrice == 0)
        #expect(added.listID == harness.viewModel.primaryListID)

        #expect(hosted.element(identifier: "cart.add_close")?.activate() == true)
        #expect(await hosted.pump { hosted.element(identifier: "cart.add") != nil })
        // The morph cross-fades; the field leaves the tree once the transition ends.
        #expect(await hosted.pump { hosted.element(identifier: "cart.add_field") == nil })
    }

    @Test("REQ-SHELL-010: the cart re-renders on session changes: sync indicator, new lines, title")
    func stateChangesReRender() async throws {
        let (fixture, harness) = try await Self.cartWithLines()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        let updating = String(localized: "cart.updating")
        #expect(!hosted.containsLabel(updating))

        harness.state.isCartSyncing = true
        #expect(await hosted.pump { hosted.containsLabel(updating) })
        harness.state.isCartSyncing = false
        #expect(await hosted.pump { !hosted.containsLabel(updating) })

        _ = try await fixture.addProduct(named: "Butter")
        harness.state.productsByListID[fixture.listID] = try fixture.products
        harness.state.contentRevision += 1
        #expect(await hosted.pump { hosted.elements(identifier: "cart.product_name").count == 4 })

        harness.state.cartTitle = "Weekend"
        #expect(await hosted.pump { hosted.uiLabelTexts.contains("Weekend") })
    }

    @Test("REQ-CART-040: a fully bought cart shows the hero card and the progress header reports completion")
    func allPurchasedShowsHeroAndProgress() async throws {
        let (_, harness) = try await Self.cartWithLines(purchased: true)
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        #expect(hosted.element(identifier: "cart.all_purchased")?.label?
            .contains(String(localized: "cart.all_purchased_title")) == true)
        #expect(hosted.element(identifier: "cart.progress")?.label?
            .contains(String(localized: "cart.all_purchased_title")) == true)
    }

    @Test("REQ-SHELL-010: progress sits at the top of the cart, above the category sections")
    func progressHeaderLeadsTheCart() async throws {
        let (_, harness) = try await Self.cartWithLines()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }
        let expected = String(localized: "cart.progress_completed \(1) \(3)")
        #expect(hosted.element(identifier: "cart.progress")?.label?.contains(expected) == true)
        let identifiers = hosted.identifiers
        let progressIndex = try #require(identifiers.firstIndex(of: "cart.progress"))
        let firstRowIndex = try #require(identifiers.firstIndex(of: "cart.product_name"))
        #expect(progressIndex < firstRowIndex)
    }

    @Test("REQ-SHARE-010: a read-only cart shows the banner and hides the composer")
    func readOnlyCartHidesComposer() async throws {
        let (_, harness) = try await Self.cartWithLines()
        harness.state.canEdit = false
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }

        #expect(hosted.element(identifier: "cart.read_only")?.label?
            .contains(String(localized: "cart.read_only_title")) == true)
        #expect(hosted.element(identifier: "cart.add") == nil)
        #expect(hosted.elements(identifier: "cart.product_toggle").allSatisfy { !$0.isEnabled })
    }
}
