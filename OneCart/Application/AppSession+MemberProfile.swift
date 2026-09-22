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

extension AppSession: MemberNamePrompting {
    var shouldPromptForMemberName: Bool {
        guard isReady, !needsWelcome, !isDeletingAccount, !memberNamePromptDeclined, let account else {
            return false
        }
        return ParticipantDisplayName.resolved(preferences: preferences, account: account) == nil
    }

    func saveMemberName(_ name: String) async {
        await updateParticipantDisplayName(name)
    }

    func declineMemberNamePrompt() {
        MemberNamePromptStorage.markDeclined(in: defaults)
        memberNamePromptDeclined = true
    }
}

/// Device-wide on purpose: "Not now" means the user does not want to be asked again here.
enum MemberNamePromptStorage {
    private static let declinedKey = "onecart.member-name-prompt-declined"

    static func isDeclined(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: declinedKey)
    }

    static func markDeclined(in defaults: UserDefaults) {
        defaults.set(true, forKey: declinedKey)
    }
}
