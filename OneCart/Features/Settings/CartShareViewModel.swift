import Combine

@MainActor
final class CartShareViewModel: ObservableObject {
    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func createFamilyInviteLink() async throws -> FamilyInviteLink {
        try await session.createFamilyInviteLink()
    }

    func removeMember(_ member: FamilyMember) async {
        await session.removeMember(member)
    }

    func leaveCurrentFamily() async {
        await session.leaveCurrentFamily()
    }
}
