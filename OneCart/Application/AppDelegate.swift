import CloudKit
import UIKit

extension Notification.Name {
    static let oneCartDidReceiveCloudKitShare = Notification.Name(
        "OneCartDidReceiveCloudKitShare"
    )
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    private static let metadataLock = NSLock()
    private static var pendingShareMetadata: [CKShare.Metadata] = []

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [
            UIApplication.LaunchOptionsKey: Any
        ]?
    ) -> Bool {
        true
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(
        _: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Self.receiveCloudKitShare(cloudKitShareMetadata)
    }

    static func receiveCloudKitShare(_ metadata: CKShare.Metadata) {
        enqueue(metadata)
        NotificationCenter.default.post(name: .oneCartDidReceiveCloudKitShare, object: nil)
    }

    static func enqueuePendingShare(from options: UIScene.ConnectionOptions) {
        guard let metadata = options.cloudKitShareMetadata else { return }
        enqueue(metadata)
    }

    static func enqueue(_ metadata: CKShare.Metadata) {
        metadataLock.lock()
        pendingShareMetadata.append(metadata)
        metadataLock.unlock()
    }

    static func takePendingShareMetadata() -> [CKShare.Metadata] {
        metadataLock.lock()
        defer { metadataLock.unlock() }
        let copy = pendingShareMetadata
        pendingShareMetadata.removeAll()
        return copy
    }

    static func requeue(_ metadata: [CKShare.Metadata]) {
        guard !metadata.isEmpty else { return }
        metadataLock.lock()
        pendingShareMetadata.append(contentsOf: metadata)
        metadataLock.unlock()
    }
}
