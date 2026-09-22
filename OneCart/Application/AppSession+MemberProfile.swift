import Foundation

extension AppSession {
    /// Shares this user's chosen name with the members of the active cart (REQ-AUTH-040).
    /// Runs on bootstrap, cart activation, share acceptance and every name change; the
    /// repository makes repeats free, so callers need not track what was published.
    func publishMemberProfile() async {
        guard let account,
              let familyID = activeFamilySpace?.id,
              persistence.isLoaded,
              !persistence.accountDeletionRecoveryRequired
        else { return }
        guard let recordName = await cloudUserIdentity.currentUserRecordName() else { return }
        currentUserRecordName = recordName
        let name = Self.participantName(preferences: preferences, account: account)
        do {
            let written = try await repository.upsertMemberProfile(
                familySpaceID: familyID,
                userRecordName: recordName,
                displayName: name
            )
            if written {
                CartSyncLog.action.info("memberProfile published")
            }
        } catch {
            CartSyncLog.action.error(
                "memberProfile fail error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
