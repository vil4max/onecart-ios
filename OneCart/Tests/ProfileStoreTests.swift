@testable import OneCart
import UIKit
import XCTest

@MainActor
final class ProfileStoreTests: XCTestCase {
    func testProfileMediaPersistsOnDeviceWithoutCloudKitBackend() throws {
        let userID = UUID()
        defer {
            ProfileMediaStore.remove(for: userID, kind: .avatar)
            ProfileMediaStore.remove(for: userID, kind: .banner)
        }

        let store = ProfileStore()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }

        try store.persistMedia(
            accountID: userID,
            avatar: image,
            banner: nil,
            removeAvatar: false,
            removeBanner: false
        )

        XCTAssertNotNil(store.avatar)
        XCTAssertNotNil(ProfileMediaStore.image(for: userID, kind: .avatar))

        let reloaded = ProfileStore()
        reloaded.reload(for: userID)
        XCTAssertNotNil(reloaded.avatar)
    }
}
