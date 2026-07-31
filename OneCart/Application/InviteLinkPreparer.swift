import CoreData
import Foundation
import OSLog

@MainActor
final class InviteLinkPreparer: ObservableObject {
    @Published private(set) var preparedInviteLink: FamilyInviteLink?
    private(set) var preparedInviteFamilyID: UUID?
    private var invitePrepareTask: Task<Void, Never>?

    func createInviteLink(
        family: FamilySpace,
        isOnline: Bool,
        fetch: () async throws -> FamilyInviteLink
    ) async throws -> FamilyInviteLink {
        guard let familyID = family.id else {
            CartSyncLog.action.error("shareInvite denied noFamily")
            throw InviteLinkError.notOwner
        }
        guard isOnline else {
            CartSyncLog.action.error("shareInvite denied offline")
            throw InviteLinkError.offline
        }

        CartSyncLog.action.info("shareInvite start family=\(familyID.uuidString, privacy: .public)")
        let link = try await fetch()
        preparedInviteLink = link
        preparedInviteFamilyID = familyID
        CartSyncLog.action.info(
            "shareInvite done host=\(link.url.host ?? "-", privacy: .public)"
        )
        return link
    }

    func schedulePreparation(
        delayNanoseconds: UInt64 = 1_500_000_000,
        isOnline: @escaping () -> Bool,
        family: @escaping () -> FamilySpace?,
        familyStillActive: @escaping (UUID) -> Bool,
        fetch: @escaping (FamilySpace) async throws -> FamilyInviteLink
    ) {
        invitePrepareTask?.cancel()
        invitePrepareTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await prepareInBackground(
                isOnline: isOnline(),
                family: family(),
                familyStillActive: familyStillActive,
                fetch: fetch
            )
        }
    }

    func clear() {
        invitePrepareTask?.cancel()
        invitePrepareTask = nil
        preparedInviteLink = nil
        preparedInviteFamilyID = nil
    }

    func shouldClearCache(forSelectedFamilyID selectedID: UUID?) -> Bool {
        guard preparedInviteLink != nil else { return false }
        if let preparedInviteFamilyID, preparedInviteFamilyID != selectedID {
            return true
        }
        return false
    }

    private func prepareInBackground(
        isOnline: Bool,
        family: FamilySpace?,
        familyStillActive: (UUID) -> Bool,
        fetch: (FamilySpace) async throws -> FamilyInviteLink
    ) async {
        guard isOnline else { return }
        guard let family, let familyID = family.id else { return }
        if let preparedInviteLink,
           preparedInviteFamilyID == familyID,
           preparedInviteLink.expiresAt > Date().addingTimeInterval(30)
        {
            return
        }

        do {
            let link = try await fetch(family)
            guard !Task.isCancelled else { return }
            guard familyStillActive(familyID) else { return }
            preparedInviteLink = link
            preparedInviteFamilyID = familyID
        } catch {}
    }
}
