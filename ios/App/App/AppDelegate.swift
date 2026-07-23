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
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]?
    ) -> Bool {
        return true
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Self.enqueue(cloudKitShareMetadata)
        NotificationCenter.default.post(name: .oneCartDidReceiveCloudKitShare, object: nil)
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
