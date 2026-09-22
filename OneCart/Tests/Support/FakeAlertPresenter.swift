import Foundation
@testable import OneCart

@MainActor
final class FakeAlertPresenter: AlertPresenting {
    var userAlert: UserAlert?
    var sharedCartRemovedMessage: String?
    var dismissAlertCount = 0
    var dismissSharedCartRemovedMessageCount = 0

    func dismissAlert() {
        dismissAlertCount += 1
        userAlert = nil
    }

    func dismissSharedCartRemovedMessage() {
        dismissSharedCartRemovedMessageCount += 1
        sharedCartRemovedMessage = nil
    }
}
