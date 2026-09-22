import Foundation
@testable import OneCart
import SwiftUI
import Testing
import UIKit

/// The shell hosted over a real `AppSession` on isolated stores: the three tabs and the root
/// switch between the launch ride, Welcome and the tabs (REQ-SHELL-010, REQ-AUTH-010).
@MainActor
@Suite("HostedShellViewTests")
struct HostedShellViewTests {
    private static var tabTitles: [String] {
        ["cart.tab", "history.tab", "account.tab"].map { String(localized: String.LocalizationValue($0)) }
    }

    @Test("REQ-SHELL-010: the main shell hosts the Cart, History and Settings tabs with the cart title")
    func mainTabsHostTheThreeScreens() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex", cartName: "Weekend")
        let hosted = HostedView(MainTabView(session: fixture.session))
        defer { hosted.tearDown() }

        #expect(await hosted.pump { !hosted.views(of: UITabBar.self).isEmpty })
        let tabBar = try #require(hosted.views(of: UITabBar.self).first)
        #expect(tabBar.items?.compactMap(\.title) == Self.tabTitles)
        #expect(await hosted.pump { hosted.uiLabelTexts.contains("Weekend") })
        #expect(hosted.element(identifier: "cart.add") != nil)
        #expect(!hosted.containsLabel(String(localized: "account.share_cart")))
    }

    @Test("REQ-AUTH-010: a signed-out root rides in and lands on Welcome")
    func signedOutRootLandsOnWelcome() async throws {
        let fixture = try await MembershipSessionFixture.signedOut()
        let hosted = HostedView(RootView().environment(fixture.session))
        defer { hosted.tearDown() }

        #expect(hosted.containsLabel(String(localized: "common.loading")))
        #expect(await hosted.pump(maxTurns: 80) { hosted.element(identifier: "welcome.app_name") != nil })
        #expect(hosted.element(identifier: "welcome.app_name")?.label == "OneCart Family")
        #expect(hosted.views(of: UITabBar.self).isEmpty)
    }

    @Test("REQ-SHELL-010: a signed-in root rides in and lands on the tabs")
    func signedInRootLandsOnTabs() async throws {
        let fixture = try await MembershipSessionFixture.owner()
        let hosted = HostedView(RootView().environment(fixture.session))
        defer { hosted.tearDown() }

        #expect(await hosted.pump(maxTurns: 80) { !hosted.views(of: UITabBar.self).isEmpty })
        #expect(hosted.element(identifier: "welcome.app_name") == nil)
        #expect(hosted.views(of: UITabBar.self).first?.items?.count == 3)
    }
}
