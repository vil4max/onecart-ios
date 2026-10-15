import Foundation

struct OneCartAccount: Equatable {
    let id: UUID
    let displayName: String
    let avatarURL: String?
    let bannerURL: String?

    init(
        id: UUID,
        displayName: String,
        avatarURL: String? = nil,
        bannerURL: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
    }
}

enum FamilyAccess: String, Equatable {
    case owner
    case member

    var canEdit: Bool {
        true
    }

    var isOwner: Bool {
        self == .owner
    }

    var isParticipant: Bool {
        self == .member
    }
}

enum OneCartSyncState: Equatable {
    case synchronized
    case syncing
    case offline
    case failed
}

struct FamilyMember: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let access: FamilyAccess
    let joinedAt: Date
    let isCurrentUser: Bool
    let avatarURL: String?
    let bannerURL: String?
}

struct FamilyInviteLink: Identifiable, Equatable {
    let id: UUID
    let familyName: String
    let url: URL

    var shareMessage: String {
        String(format: String(localized: "share.message"), familyName, url.absoluteString)
    }

    var shareTitle: String {
        OneCartShareBranding.title
    }
}
