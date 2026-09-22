import CoreData
import Foundation
@testable import OneCart
import Testing

/// The negative requirements: what the product must not offer. Each test pins the constraint
/// at the layer where it lives (ViewModel API, protocol surface, bundle metadata); the hosted
/// suites under `HostedViews/` prove the same constraints on the rendered screens.
@MainActor
@Suite("RequirementConstraintTests")
struct RequirementConstraintTests {

    // MARK: - REQ-CART-060 name-only items

    @Test("REQ-CART-060: a name-only add and a rename never carry a price into the cart")
    func addAndRenameCarryNoPrice() async throws {
        let fixture = try await CartFixture.make()
        let breadID = try await fixture.addProduct(named: "Bread")
        let harness = try CartHarness(fixture: fixture)
        harness.cart.addResult = UUID()

        let outcome = await harness.viewModel.addItem(named: "  Milk  ")

        #expect(outcome != .rejected)
        let added = try #require(harness.cart.addedProducts.first)
        #expect(added.draft.name == "Milk")
        #expect(added.draft.quantity == 1)
        #expect(added.draft.unit == .piece)
        #expect(added.draft.estimatedPrice == 0)
        #expect(added.draft.originalPrice == nil)
        #expect(added.draft.loyaltyPrice == nil)
        #expect(added.draft.note.isEmpty)

        let bread = try fixture.product(id: breadID)
        #expect(bread.estimatedPriceValue == 0)
        #expect(await harness.viewModel.rename(bread, to: "Rye bread"))
        let renamed = try #require(harness.cart.updatedProducts.first)
        #expect(renamed.draft.name == "Rye bread")
        #expect(renamed.draft.estimatedPrice == 0)
        #expect(renamed.draft.originalPrice == nil)
        #expect(renamed.draft.loyaltyPrice == nil)
    }

    // MARK: - REQ-HIST-050 History is never user-cleared

    @Test("REQ-HIST-050: browsing History through its ViewModel never removes an entry; paging is the only call")
    func historyViewModelHasNoClearingAction() async throws {
        // `HistoryBrowsing` declares `history`, `historyHasMore` and `loadMoreHistory()` only, and
        // `FakeHistoryBrowser` implements exactly those: a clearing requirement added to the
        // protocol would break the fake's conformance and this suite's compile.
        let fixture = try await CartFixture.make()
        for name in ["Bread", "Milk"] {
            _ = try await fixture.addProduct(named: name, purchased: true)
        }
        _ = try await fixture.repository.completePurchased(listID: fixture.listID)
        await fixture.settle()
        let browser = FakeHistoryBrowser()
        browser.history = try fixture.history
        browser.historyHasMore = true
        let entriesBefore = browser.history
        let persistedBefore = try fixture.history.count
        let viewModel = HistoryViewModel(history: browser)

        // Every member of the ViewModel's API, in declaration order.
        let groups = viewModel.dayGroups
        _ = viewModel.isEmpty
        _ = viewModel.hasMore
        viewModel.loadMore()
        let day = try #require(groups.first)
        let live = viewModel.liveGroup(for: day)
        await fixture.settle()

        #expect(live.items.map(\.displayName) == ["Bread", "Milk"])
        #expect(browser.loadMoreCount == 1)
        #expect(browser.history == entriesBefore)
        #expect(try fixture.history.count == persistedBefore)
    }

    // MARK: - REQ-SHARE-100 no invented Apple Family APIs

    @Test("REQ-SHARE-100: membership runs on CKShare links and participants, never on an Apple Family roster")
    func membershipSurfaceIsCloudKitOnly() async throws {
        // `FakeMembershipManager` implements exactly the seven `MembershipManaging` requirements
        // (invite link, revoke, rename, remove, leave, refresh, error text). A requirement to list
        // Family members, verify a shared Family or push a share to a whole Family would break the
        // fake's conformance and this suite's compile. Limit: the compile check cannot see calls
        // made outside the protocol; `appSourcesReferenceNoFamilyAPIs` scans the app sources for those.
        let fixture = try await CartFixture.make()
        let isolated = try IsolatedPreferences()
        let state = FakeSessionState(preferences: isolated.preferences)
        state.account = OneCartAccount(id: UUID(), displayName: "Alex")
        state.activeFamilySpace = try fixture.family
        state.access = .owner
        let membership = FakeMembershipManager()
        let link = try FamilyInviteLink(
            id: UUID(),
            familyName: "Family",
            url: #require(URL(string: "https://www.icloud.com/share/0abc#Family"))
        )
        membership.inviteLinkResult = .success(link)
        let viewModel = AccountViewModel(
            state: state,
            membership: membership,
            account: FakeAccountManager(),
            iconSwitcher: FakeAppIconSwitcher()
        )

        viewModel.shareCart()
        for _ in 0 ..< 1000 where viewModel.sharePayload == nil {
            await Task.yield()
        }

        #expect(membership.createInviteLinkCount == 1)
        #expect(viewModel.sharePayload?.link == link)
        #expect(link.shareTitle == OneCartShareBranding.title)
        #expect(link.shareMessage.contains(link.url.absoluteString))

        // The member list is the CKShare participant list the session read, nothing system-wide.
        let participants = [
            FamilyMember(
                id: UUID(), displayName: "Alex", access: .owner, joinedAt: Date(),
                isCurrentUser: true, avatarURL: nil, bannerURL: nil
            ),
            FamilyMember(
                id: UUID(), displayName: "Sam", access: .member, joinedAt: Date(),
                isCurrentUser: false, avatarURL: nil, bannerURL: nil
            ),
        ]
        state.familyMembers = participants
        #expect(viewModel.displayedMembers == participants)
        await viewModel.removeMember(participants[1])
        #expect(membership.removedMembers == [participants[1]])
    }

    @Test("REQ-SHARE-100: the app sources import no Family framework and name no Family-roster API")
    func appSourcesReferenceNoFamilyAPIs() throws {
        // Symbols that would mean the code pretends Apple exposes a Family roster. `FamilyControls`
        // and `ManagedSettings` are Screen Time frameworks, the only public ones with "Family" in
        // their name; the rest are private-framework class prefixes.
        let forbidden = ["FamilyControls", "ManagedSettings", "FAFamilyCircle", "FamilyCircle", "FAFamily"]
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // OneCart (module sources)
        let enumerator = try #require(FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ))
        var scanned = 0
        var hits: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !url.path.contains("/Tests/") else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            for symbol in forbidden where text.contains(symbol) {
                hits.append("\(url.lastPathComponent): \(symbol)")
            }
        }
        #expect(scanned > 50, "expected the app sources next to the test folder, scanned \(scanned) files")
        #expect(hits.isEmpty, "Family-API references: \(hits)")
    }

    // MARK: - REQ-SHELL-060 OneCart Family branding

    @Test("REQ-SHELL-060: the app presents itself as OneCart Family while the module and bundle id stay OneCart")
    func brandingIsOneCartFamily() {
        // The test host is OneCart.app, so `Bundle.main` is the shipped bundle.
        let bundle = Bundle.main
        #expect(bundle.bundleIdentifier == "com.vil555tim.onecart")
        #expect(bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "OneCart Family")
        #expect(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String == "OneCart")
        for identifier in ["en", "ru", "uk"] {
            let locale = Locale(identifier: identifier)
            #expect(String(localized: "common.app_name", locale: locale) == "OneCart Family")
            #expect(
                bundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist")
                    == "OneCart Family"
            )
        }
        #expect(OneCartShareBranding.title == "OneCart Family")
    }
}
