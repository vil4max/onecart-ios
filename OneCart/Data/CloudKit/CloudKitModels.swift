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

    var title: String {
        switch self {
        case .owner: String(localized: "cart.owner_role")
        case .member: String(localized: "cart.member_role")
        }
    }

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

    var title: String {
        switch self {
        case .synchronized: String(localized: "sync.synchronized")
        case .syncing: String(localized: "sync.syncing")
        case .offline: String(localized: "sync.offline")
        case .failed: String(localized: "sync.failed")
        }
    }

    var systemImage: String {
        switch self {
        case .synchronized: "checkmark.circle.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.circle.fill"
        }
    }
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

    var expiresAt: Date {
        .distantFuture
    }

    var shareMessage: String {
        String(format: String(localized: "share.message"), familyName, url.absoluteString)
    }

    var shareTitle: String {
        OneCartShareBranding.title
    }
}
