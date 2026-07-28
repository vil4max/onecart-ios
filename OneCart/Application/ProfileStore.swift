import Foundation
import UIKit

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var avatar: UIImage?
    @Published private(set) var banner: UIImage?

    func clear() {
        avatar = nil
        banner = nil
    }

    func reload(for userID: UUID) {
        avatar = ProfileMediaStore.image(for: userID, kind: .avatar)
        banner = ProfileMediaStore.image(for: userID, kind: .banner)
    }

    func persistMedia(
        accountID: UUID,
        avatar: UIImage?,
        banner: UIImage?,
        removeAvatar: Bool,
        removeBanner: Bool
    ) throws {
        if removeAvatar {
            ProfileMediaStore.remove(for: accountID, kind: .avatar)
        } else if let avatar {
            try ProfileMediaStore.save(avatar, for: accountID, kind: .avatar)
        }

        if removeBanner {
            ProfileMediaStore.remove(for: accountID, kind: .banner)
        } else if let banner {
            try ProfileMediaStore.save(banner, for: accountID, kind: .banner)
        }
        reload(for: accountID)
    }
}
