import CloudKit
import Foundation
@testable import OneCart
import Testing
import UserNotifications

extension AccountViewModelFakeTests {
    @Test("REQ-SHARE-030: an error from a timed-out share does not replace the timeout alert")
    func lateErrorAfterTimeoutKeepsTheTimeoutAlert() async throws {
        struct LateFailure: Error {}
        @MainActor final class Flag {
            var isSet = false
        }
        let isolated = try IsolatedPreferences()
        let state = FakeSessionState(preferences: isolated.preferences)
        let membership = FakeMembershipManager()
        let lateFailure = Flag()
        membership.inviteLinkOperation = {
            // Waits until the watchdog cancels the request, then fails with something else.
            while !Task.isCancelled {
                await Task.yield()
            }
            lateFailure.isSet = true
            throw LateFailure()
        }
        let clock = TestClock()
        let viewModel = AccountViewModel(
            state: state,
            membership: membership,
            account: FakeAccountManager(),
            iconSwitcher: FakeAppIconSwitcher(),
            clock: clock.appClock
        )

        viewModel.shareCart()
        #expect(await clock.waitForSleepers())
        clock.advance(by: AccountViewModel.defaultShareTimeout)
        for _ in 0..<10_000 where !lateFailure.isSet {
            await Task.yield()
        }
        await Task.yield()

        #expect(lateFailure.isSet)
        #expect(viewModel.isSharing == false)
        #expect(viewModel.shareAlert == .error(try #require(OneCartCloudKitError.shareTimedOut.errorDescription)))
        #expect(membership.describedErrors.isEmpty)
    }

    @Test("REQ-SHELL-050: a production-schema failure shows the schema-missing alert")
    func productionSchemaFailureShowsSchemaAlert() async throws {
        let harness = try AccountHarness()
        harness.membership.inviteLinkResult = .failure(
            NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.partialFailure.rawValue,
                userInfo: [
                    NSLocalizedDescriptionKey: "Partial Failure",
                    "CKErrorDescription": "Cannot create new type CD_ShoppingList in production schema",
                ]
            )
        )

        harness.viewModel.shareCart()
        await harness.awaitShareCompletion()

        #expect(harness.viewModel.shareAlert == .error(CloudKitUserFacingError.productionSchemaMissing))
        #expect(harness.membership.describedErrors.isEmpty)
        #expect(!harness.viewModel.isSharing)
    }

    @Test("REQ-WIDGET-030: each Settings appearance asks for notification permission through the ViewModel")
    func appearanceRequestsNotificationAuthorization() async throws {
        let harness = try AccountHarness()

        await harness.viewModel.onAppear()
        #expect(harness.notificationRequests.count == 1)
        #expect(harness.membership.refreshAccountSharingCount == 1)

        await harness.viewModel.onAppear()
        #expect(harness.notificationRequests.count == 2)
        #expect(harness.membership.refreshAccountSharingCount == 2)
    }

    @Test("REQ-WIDGET-030: activity notifications ask for alert and sound, not badge")
    func notificationPermissionOmitsBadge() {
        #expect(CartActivityNotifier.authorizationOptions == [.alert, .sound])
        #expect(!CartActivityNotifier.authorizationOptions.contains(.badge))
    }
}
