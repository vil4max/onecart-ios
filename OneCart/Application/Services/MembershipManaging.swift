import Foundation

/// Invite door, members and the active cart's identity, as managed from Settings.
@MainActor
protocol MembershipManaging: AnyObject {
    func createFamilyInviteLink() async throws -> FamilyInviteLink
    func revokeInviteLink() async
    func renameActiveCart(_ rawName: String) async
    func removeMember(_ member: FamilyMember) async
    func leaveCurrentFamily() async
    func refreshAccountSharing() async
    func userFacingMessage(for error: Error) -> String
}
