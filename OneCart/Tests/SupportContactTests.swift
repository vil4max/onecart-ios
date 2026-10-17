import Foundation
@testable import OneCart
import Testing

/// The support row in Settings and the email it prepares (REQ-SHELL-070).
@MainActor
@Suite("SupportContactTests", .removesStores)
struct SupportContactTests {
    private let version = AppVersionInfo(version: "9.8.7", build: "42")

    @Test("REQ-SHELL-070: the email goes to the published address with the subject, version and build")
    func mailURLAddressesSupportWithVersionAndBuild() throws {
        let contact = SupportContact.published
        let body = SupportContact.mailBody(appName: "OneCart Family", appVersion: version)
        let url = try #require(contact.mailURL(subject: "OneCart Family support", body: body))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "mailto")
        #expect(components.path == contact.emailAddress)
        let items = components.queryItems ?? []
        #expect(items.first { $0.name == "subject" }?.value == "OneCart Family support")
        let sentBody = try #require(items.first { $0.name == "body" }?.value)
        #expect(sentBody.hasSuffix("OneCart Family 9.8.7 (42)"))
        // Room to write comes before the version line.
        #expect(sentBody.hasPrefix("\n\n"))
    }

    @Test("REQ-SHELL-070: a translated subject keeps &, = and + inside its own value")
    func reservedCharactersStayInsideTheirValue() throws {
        let subject = "Поддержка & вопросы = 1+1"
        let url = try #require(SupportContact.published.mailURL(subject: subject, body: "a&body=b"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.map(\.name) == ["subject", "body"])
        #expect(items[0].value == subject)
        #expect(items[1].value == "a&body=b")
    }

    @Test("REQ-SHELL-070: the address in the app is the contact the privacy policy publishes")
    func addressMatchesThePrivacyPolicy() throws {
        let policy = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // OneCart (module sources)
            .deletingLastPathComponent()  // repository root
            .appending(path: "docs/privacy.md")
        let text = try String(contentsOf: policy, encoding: .utf8)
        #expect(text.contains("**Contact:** \(SupportContact.published.emailAddress)"))
    }

    @Test(
        "REQ-SHELL-070: every member's Settings ends with the support row, after the account, above the version",
        arguments: [FamilyAccess.owner, .member]
    )
    func settingsEndsWithTheSupportRow(access: FamilyAccess) async throws {
        let harness = try await HostedAccountHarness(access: access)
        // Tall enough for the whole Form: scrolled-away cells are recycled out of the tree.
        let hosted = HostedView(
            AccountView(viewModel: harness.viewModel),
            size: CGSize(width: HostedView.phoneSize.width, height: 2000)
        )
        defer { hosted.tearDown() }

        let support = try #require(hosted.element(identifier: "account.support"))
        #expect(support.isButton)
        #expect(support.isEnabled)
        #expect(support.label == String(localized: "settings.support_row"))
        #expect(hosted.containsLabel(String(localized: "settings.support_section")))
        let identifiers = hosted.identifiers
        let deleteIndex = try #require(identifiers.firstIndex(of: "account.delete_account"))
        let supportIndex = try #require(identifiers.firstIndex(of: "account.support"))
        let versionIndex = try #require(identifiers.firstIndex(of: "account.version"))
        #expect(deleteIndex < supportIndex)
        #expect(supportIndex < versionIndex)
    }
}
