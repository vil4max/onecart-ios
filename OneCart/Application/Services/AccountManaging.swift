import Foundation

/// The signed-in account's lifecycle and device-local display name.
@MainActor
protocol AccountManaging: AnyObject {
    func signOut()
    func deleteAccount() async
    func updateParticipantDisplayName(_ raw: String) async
}
