import Foundation
@testable import OneCart
import Testing

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
        let viewModel = AccountViewModel(
            state: state,
            membership: membership,
            account: FakeAccountManager(),
            iconSwitcher: FakeAppIconSwitcher(),
            shareTimeoutNanoseconds: 1_000_000
        )

        viewModel.shareCart()
        for _ in 0..<100_000 where !lateFailure.isSet {
            await Task.yield()
        }
        await Task.yield()

        #expect(lateFailure.isSet)
        #expect(viewModel.isSharing == false)
        #expect(viewModel.shareAlert == .error(try #require(OneCartCloudKitError.shareTimedOut.errorDescription)))
        #expect(membership.describedErrors.isEmpty)
    }
}
