import Foundation
@testable import OneCart

@MainActor
@Observable
final class FakeMemberNamePrompter: MemberNamePrompting {
    var shouldPromptForMemberName = true
    var savedNames: [String] = []
    var declineCount = 0

    func saveMemberName(_ name: String) async {
        savedNames.append(name)
        shouldPromptForMemberName = false
    }

    func declineMemberNamePrompt() {
        declineCount += 1
        shouldPromptForMemberName = false
    }
}
