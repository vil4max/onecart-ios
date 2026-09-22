import Foundation
@testable import OneCart

@MainActor
final class FakeAccountManager: AccountManaging {
    var signOutCount = 0
    var deleteAccountCount = 0
    var updatedDisplayNames: [String] = []

    func signOut() {
        signOutCount += 1
    }

    func deleteAccount() async {
        deleteAccountCount += 1
    }

    func updateParticipantDisplayName(_ raw: String) async {
        updatedDisplayNames.append(raw)
    }
}
