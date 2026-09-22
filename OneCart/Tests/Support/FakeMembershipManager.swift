import Foundation
@testable import OneCart

@MainActor
final class FakeMembershipManager: MembershipManaging {
    struct NoInviteConfigured: Error {}

    var inviteLinkResult: Result<FamilyInviteLink, any Error> = .failure(NoInviteConfigured())
    var createInviteLinkCount = 0
    var revokeInviteLinkCount = 0
    var renamedCartNames: [String] = []
    var removedMembers: [FamilyMember] = []
    var leaveCount = 0
    var refreshAccountSharingCount = 0
    var userFacingMessage = "Something went wrong"
    var describedErrors: [any Error] = []

    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        createInviteLinkCount += 1
        return try inviteLinkResult.get()
    }

    func revokeInviteLink() async {
        revokeInviteLinkCount += 1
    }

    func renameActiveCart(_ rawName: String) async {
        renamedCartNames.append(rawName)
    }

    func removeMember(_ member: FamilyMember) async {
        removedMembers.append(member)
    }

    func leaveCurrentFamily() async {
        leaveCount += 1
    }

    func refreshAccountSharing() async {
        refreshAccountSharingCount += 1
    }

    func userFacingMessage(for error: any Error) -> String {
        describedErrors.append(error)
        return userFacingMessage
    }
}
