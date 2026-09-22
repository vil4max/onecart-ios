import CloudKit
import Foundation

/// What the members list needs from one `CKShare.Participant`.
struct ShareParticipantSummary: Equatable {
    let recordName: String
    /// The iCloud name, when CloudKit shares it; usually empty for link-joined participants.
    let identityName: String?
    let isOwner: Bool
    let isCurrentUser: Bool
}

/// Names share participants for the members list (REQ-AUTH-040).
enum FamilyMemberNaming {
    static func members(
        participants: [ShareParticipantSummary],
        profileNames: [String: String],
        currentUserRecordName: String?,
        account: OneCartAccount,
        joinedAt: Date
    ) -> [FamilyMember] {
        // Owner first, then by record name: labels stay put however CloudKit orders participants.
        let ordered = participants.sorted {
            if $0.isOwner != $1.isOwner {
                return $0.isOwner
            }
            return $0.recordName < $1.recordName
        }
        return ordered.enumerated().map { index, participant in
            let isCurrent = participant.isCurrentUser
                || participant.recordName == CKCurrentUserDefaultName
                || participant.recordName == currentUserRecordName
            let displayName = if isCurrent {
                account.displayName
            } else {
                profileNames[participant.recordName]?.nonBlankMemberName
                    ?? participant.identityName?.nonBlankMemberName
                    ?? String(localized: "members.numbered_fallback \(index + 1)")
            }
            return FamilyMember(
                id: FamilyInviteLinkBuilder.stableUUID(for: participant.recordName),
                displayName: displayName,
                access: participant.isOwner ? .owner : .member,
                joinedAt: joinedAt,
                isCurrentUser: isCurrent,
                avatarURL: nil,
                bannerURL: nil
            )
        }
        .sorted {
            if $0.access != $1.access {
                return $0.access == .owner
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

private extension String {
    var nonBlankMemberName: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
