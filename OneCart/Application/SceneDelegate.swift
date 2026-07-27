import CloudKit
import UIKit

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        AppDelegate.enqueuePendingShare(from: connectionOptions)
    }

    func windowScene(
        _: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        AppDelegate.receiveCloudKitShare(cloudKitShareMetadata)
    }
}
