import CloudKit
import UIKit

extension Notification.Name {
    static let oneCartDidReceiveCloudKitShare = Notification.Name(
        "OneCartDidReceiveCloudKitShare"
    )
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    private(set) static var pendingShareMetadata: [CKShare.Metadata] = []

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
        Self.pendingShareMetadata.append(cloudKitShareMetadata)
        NotificationCenter.default.post(name: .oneCartDidReceiveCloudKitShare, object: nil)
    }

    static func takePendingShareMetadata() -> [CKShare.Metadata] {
        defer { pendingShareMetadata.removeAll() }
        return pendingShareMetadata
    }
}
