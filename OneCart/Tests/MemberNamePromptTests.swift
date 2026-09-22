import CoreData
import Foundation
@testable import OneCart
import SwiftUI
import Testing

/// The one-time "What should your family call you?" prompt when Apple gives no name (REQ-AUTH-040).
@MainActor
@Suite("MemberNamePromptTests")
struct MemberNamePromptTests {

    // MARK: - ViewModel

    @Test("REQ-AUTH-040: the prompt is presented while the session asks for a name")
    func presentedWhileSessionAsks() {
        let prompter = FakeMemberNamePrompter()
        let viewModel = MemberNamePromptViewModel(prompting: prompter)
        #expect(viewModel.isPresented)

        prompter.shouldPromptForMemberName = false
        #expect(!viewModel.isPresented)
    }

    @Test("REQ-AUTH-040: Save sends the trimmed name and never a placeholder")
    func saveSendsTrimmedNameOnly() async {
        let prompter = FakeMemberNamePrompter()
        let viewModel = MemberNamePromptViewModel(prompting: prompter)

        viewModel.name = "   "
        #expect(!viewModel.canSave)
        await viewModel.save()
        viewModel.name = ParticipantDisplayName.placeholder
        #expect(!viewModel.canSave)
        await viewModel.save()
        #expect(prompter.savedNames.isEmpty)

        viewModel.name = "  Мама "
        #expect(viewModel.canSave)
        await viewModel.save()
        #expect(prompter.savedNames == ["Мама"])
        #expect(!viewModel.isPresented)
        #expect(prompter.declineCount == 0)
    }

    @Test("REQ-AUTH-040: Not now declines, and a swipe-down counts as Not now")
    func notNowDeclines() {
        let prompter = FakeMemberNamePrompter()
        let viewModel = MemberNamePromptViewModel(prompting: prompter)

        viewModel.handleDismissal()
        #expect(prompter.declineCount == 1)

        viewModel.notNow()
        #expect(prompter.declineCount == 1, "a dismissed prompt is not declined twice")

        prompter.shouldPromptForMemberName = true
        viewModel.notNow()
        #expect(prompter.declineCount == 2)
        #expect(prompter.savedNames.isEmpty)
    }

    // MARK: - Session

    @Test("REQ-AUTH-040: the session asks for a name only while the resolved name is a placeholder")
    func sessionAsksOnlyForPlaceholder() async throws {
        let unnamed = try await MembershipSessionFixture.owner(displayName: ParticipantDisplayName.placeholder)
        #expect(unnamed.session.shouldPromptForMemberName)

        let named = try await MembershipSessionFixture.owner(displayName: "Alex")
        #expect(!named.session.shouldPromptForMemberName)

        unnamed.session.needsWelcome = true
        #expect(!unnamed.session.shouldPromptForMemberName)
    }

    @Test("REQ-AUTH-040: Not now is remembered and the prompt never returns")
    func notNowIsRemembered() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: ParticipantDisplayName.placeholder)

        fixture.session.declineMemberNamePrompt()

        #expect(!fixture.session.shouldPromptForMemberName)
        let suiteName = "OneCartNamePrompt.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let relaunched = AppSession(
            persistence: fixture.persistence,
            preferences: DevicePreferences(defaults: fixture.defaults),
            defaults: fixture.defaults,
            appleSignIn: InMemoryAppleSignIn(),
            widgetStore: WidgetSnapshotStore(
                suiteName: suiteName,
                pendingDirectoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(suiteName, isDirectory: true)
            )
        )
        try relaunched.bootstrapTestingSession(account: fixture.account)
        #expect(!relaunched.shouldPromptForMemberName)
    }

    @Test("REQ-AUTH-040: saving from the prompt sets the name and shares it with the cart")
    func savingSetsAndSharesName() async throws {
        let fixture = try await MembershipSessionFixture.owner(
            displayName: ParticipantDisplayName.placeholder,
            cloudUserIdentity: FakeCloudUserIdentity(recordName: "_alex")
        )

        await fixture.session.saveMemberName("Мама")

        #expect(!fixture.session.shouldPromptForMemberName)
        #expect(fixture.session.account?.displayName == "Мама")
        #expect(fixture.session.preferences.participantDisplayName == "Мама")
        let persistence = fixture.persistence
        let names = try await persistence.performBackgroundTask { context in
            try context.fetch(MemberProfileEntity.fetchRequest()).map(\.displayName)
        }
        #expect(names == ["Мама"])
    }

    // MARK: - View

    @Test("REQ-AUTH-040: the prompt shows the question, the field, Save and Not now")
    func hostedPromptShowsControls() async throws {
        let prompter = FakeMemberNamePrompter()
        let viewModel = MemberNamePromptViewModel(prompting: prompter)
        let hosted = HostedView(MemberNamePromptView(viewModel: viewModel))
        defer { hosted.tearDown() }

        #expect(await hosted.pump { hosted.element(identifier: "name_prompt.not_now") != nil })
        #expect(hosted.containsLabel(String(localized: "name_prompt.title")))
        #expect(hosted.element(identifier: "name_prompt.field") != nil)
        #expect(hosted.element(identifier: "name_prompt.save") != nil)

        let notNow = try #require(hosted.element(identifier: "name_prompt.not_now"))
        #expect(notNow.activate())
        #expect(await hosted.pump { prompter.declineCount == 1 })
    }

    @Test("REQ-AUTH-040: a root signed in without a name asks after the ride, and Not now closes it")
    func rootPresentsPromptForUnnamedAccount() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: ParticipantDisplayName.placeholder)
        let hosted = HostedView(RootView().environment(fixture.session))
        defer { hosted.tearDown() }

        #expect(await hosted.pump(maxTurns: 120) { hosted.element(identifier: "name_prompt.not_now") != nil })
        let notNow = try #require(hosted.element(identifier: "name_prompt.not_now"))
        #expect(notNow.activate())
        #expect(await hosted.pump(maxTurns: 120) { hosted.element(identifier: "name_prompt.not_now") == nil })
        #expect(fixture.session.memberNamePromptDeclined)
    }
}
