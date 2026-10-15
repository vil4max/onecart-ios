import Foundation

extension AppSession {
    static func participantName(
        preferences: DevicePreferences,
        account: OneCartAccount?
    ) -> String? {
        ParticipantDisplayName.resolved(preferences: preferences, account: account)
    }

    func updateParticipantDisplayName(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRetitlePersonalCart = personalCartStillFollowsParticipantName()
        if ParticipantDisplayName.isPlaceholder(trimmed) {
            preferences.participantDisplayName = ""
            if let account {
                self.account = OneCartAccount(
                    id: account.id,
                    displayName: ParticipantDisplayName.placeholder,
                    avatarURL: account.avatarURL,
                    bannerURL: account.bannerURL
                )
            }
        } else {
            preferences.participantDisplayName = trimmed
            if let account {
                self.account = OneCartAccount(
                    id: account.id,
                    displayName: trimmed,
                    avatarURL: account.avatarURL,
                    bannerURL: account.bannerURL
                )
            }
            if let index = familyMembers.firstIndex(where: \.isCurrentUser) {
                let member = familyMembers[index]
                familyMembers[index] = FamilyMember(
                    id: member.id,
                    displayName: trimmed,
                    access: member.access,
                    joinedAt: member.joinedAt,
                    isCurrentUser: true,
                    avatarURL: member.avatarURL,
                    bannerURL: member.bannerURL
                )
            }
        }
        if shouldRetitlePersonalCart {
            await syncPersonalCartNameWithParticipant()
        }
        await schedulePublishMemberProfile().value
    }

    private func personalCartStillFollowsParticipantName() -> Bool {
        guard let account else { return false }
        guard let personal = personalFamilySpace(for: account) else { return false }
        return personal.displayName == Self.householdCartName(for: account)
    }

    private func personalFamilySpace(for account: OneCartAccount) -> FamilySpace? {
        let spaces = (try? repository.fetchFamilySpaces(for: account.id)) ?? []
        let personalSpaces = spaces.filter {
            persistence.scope(for: $0) == .private && $0.cachedForUserID == account.id
        }
        let preferredID =
            activeFamilySpace.flatMap { family in
                persistence.scope(for: family) == .private ? family.id : nil
            } ?? household.restoredPersonalFamilyID(accountID: account.id)
        return personalSpaces.first(where: { $0.id == preferredID })
            ?? personalSpaces.first(where: \.isHouseholdDefaultValue) ?? personalSpaces.first
    }

    private func syncPersonalCartNameWithParticipant() async {
        guard let account,
            let personal = personalFamilySpace(for: account),
            let familyID = personal.id
        else { return }

        let newName = Self.householdCartName(for: account)
        guard personal.displayName != newName else { return }

        do {
            try await repository.renameFamilySpace(id: familyID, name: newName)
            try reload(preferredFamilySpaceID: activeFamilySpace?.id ?? familyID)
            if activeFamilySpace?.id == familyID {
                clearPreparedInviteLink()
                scheduleInviteLinkPreparation()
            }
        } catch {
            show(error)
        }
    }
}
