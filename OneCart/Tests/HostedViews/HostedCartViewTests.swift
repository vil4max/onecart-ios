import CoreData
import Foundation
@testable import OneCart
import SwiftUI
import Testing
import UIKit

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

    @Test("REQ-WIDGET-040: the progress header offers the shopping trip, starts it, then offers to end it")
    func progressHeaderStartsTheShoppingTrip() async throws {
        let (_, harness) = try await Self.cartWithLines()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel))
        defer { hosted.tearDown() }

        let control = try #require(hosted.element(identifier: "cart.shoppingTrip"))
        #expect(control.label?.contains(String(localized: "trip.start_button")) == true)
        #expect(control.activate())
        #expect(await hosted.pump { harness.trip.startCount == 1 })
        #expect(await hosted.pump {
            hosted.element(identifier: "cart.shoppingTrip")?.label?
                .contains(String(localized: "trip.end_button")) == true
        })
    }

    @Test(
        "REQ-WIDGET-040: the trip control sits beside the progress, and below it at accessibility text sizes",
        arguments: [DynamicTypeSize.large, .accessibility3]
    )
    func progressHeaderStacksAtAccessibilitySizes(size: DynamicTypeSize) async throws {
        let (_, harness) = try await Self.cartWithLines()
        let hosted = HostedView(HomeView(viewModel: harness.viewModel).environment(\.dynamicTypeSize, size))
        defer { hosted.tearDown() }

        let progress = try #require(hosted.element(identifier: "cart.progress")).node.accessibilityFrame
        let control = try #require(hosted.element(identifier: "cart.shoppingTrip")).node.accessibilityFrame
        if size.isAccessibilitySize {
            #expect(control.minY >= progress.maxY - 1, "progress \(progress), control \(control)")
        } else {
            #expect(
                progress.minY < control.midY && control.midY < progress.maxY,
                "progress \(progress), control \(control)"
            )
        }
    }

    @Test(
        "REQ-CART-130: the name spans the row's content width at accessibility sizes, and the current layout at .large",
        arguments: [DynamicTypeSize.large, .accessibility1, .accessibility3, .accessibility5]
    )
    func productNameSpansRowContentWidth(size: DynamicTypeSize) async throws {
        // A dedicated single-line fixture, kept local to this test, so the row's name and
        // toggle elements are unambiguous; the shared `cartWithLines()` fixture is untouched.
        let fixture = try await CartFixture.make()
        _ = try await fixture.addProduct(named: "Апельсиновый сок")
        let harness = try CartHarness(fixture: fixture)
        harness.state.activeFamilySpace = try fixture.family
        harness.state.cartTitle = "Family"
        let hosted = HostedView(HomeView(viewModel: harness.viewModel).environment(\.dynamicTypeSize, size))
        defer { hosted.tearDown() }

        let nameFrame = try #require(hosted.element(identifier: "cart.product_name")).node.accessibilityFrame
        let toggleFrame = try #require(hosted.element(identifier: "cart.product_toggle")).node.accessibilityFrame

        if size.isAccessibilitySize {
            // Row content width: there is no accessibility identifier on the row itself (the
            // category tile is `accessibilityHidden`), so this is the union of the name and
            // toggle frames — the row's leading edge to its trailing edge. With the fixed
            // layout the tile and toggle share a line above the name, and the name spans the
            // same leading-to-trailing width below them, so the two widths converge.
            let rowContentWidth = max(nameFrame.maxX, toggleFrame.maxX) - min(nameFrame.minX, toggleFrame.minX)
            #expect(
                abs(nameFrame.width - rowContentWidth) < 1,
                "name \(nameFrame), row content width \(rowContentWidth)"
            )

            if size == .accessibility1 || size == .accessibility3 {
                // The word must fit the name column itself (`cart.product_name`'s own frame),
                // not the wider row content width: that is the actual box the name's text
                // wraps inside, so this is what would catch a mid-word break.
                let category = size.uiContentSizeCategoryForMeasurement
                let font = UIFont.preferredFont(
                    forTextStyle: .body,
                    compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
                )
                let wordWidth = ("Апельсиновый" as NSString).size(withAttributes: [.font: font]).width
                #expect(
                    wordWidth <= nameFrame.width + 1,
                    "word width \(wordWidth), name width \(nameFrame.width)"
                )
            }
        } else {
            // At .large the current layout holds: the name and the toggle sit on the same line.
            #expect(
                toggleFrame.minY < nameFrame.midY && nameFrame.midY < toggleFrame.maxY,
                "name \(nameFrame), toggle \(toggleFrame)"
            )
        }
    }

    @Test(
        "REQ-CART-130: the name reads before the toggle at accessibility sizes",
        arguments: [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5]
    )
    func productNameReadsBeforeToggleAtAccessibilitySizes(size: DynamicTypeSize) async throws {
        // The toggle's own accessibility label ("mark/unmark in trolley") never names the item,
        // so VoiceOver must reach the name first; the row's identifiers appear in the hosted
        // element list in the order VoiceOver would announce them (HostedView.elements walks
        // the accessibility tree in the order `accessibilityElements` reports it).
        let fixture = try await CartFixture.make()
        _ = try await fixture.addProduct(named: "Апельсиновый сок")
        let harness = try CartHarness(fixture: fixture)
        harness.state.activeFamilySpace = try fixture.family
        harness.state.cartTitle = "Family"
        let hosted = HostedView(HomeView(viewModel: harness.viewModel).environment(\.dynamicTypeSize, size))
        defer { hosted.tearDown() }

        let identifiers = hosted.identifiers
        let nameIndex = try #require(identifiers.firstIndex(of: "cart.product_name"))
        let toggleIndex = try #require(identifiers.firstIndex(of: "cart.product_toggle"))
        #expect(nameIndex < toggleIndex, "identifiers in order: \(identifiers)")
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

private extension DynamicTypeSize {
    /// `UIFont.preferredFont(compatibleWith:)` reads `UIContentSizeCategory`, not
    /// `DynamicTypeSize`; the two enums share the same ordinal steps from their first
    /// accessibility size to their last, so this maps each size REQ-CART-130 measures to its
    /// matching category.
    var uiContentSizeCategoryForMeasurement: UIContentSizeCategory {
        switch self {
        case .accessibility1: .accessibilityMedium
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        default: .large
        }
    }
}
