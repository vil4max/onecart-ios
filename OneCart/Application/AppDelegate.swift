import CloudKit
import UIKit

extension Notification.Name {
    static let oneCartDidReceiveCloudKitShare = Notification.Name(
        "OneCartDidReceiveCloudKitShare"
    )
}

final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let metricKitLogger = MetricKitLogger()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard !TestHost.isRunningUnitTests else { return true }
        metricKitLogger.start()
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification _: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // NSPersistentCloudKitContainer imports CloudKit changes on its own; this handler
        // fetches nothing, so it never reports new data.
        completionHandler(.noData)
    }

    /// UserNotifications may call its delegate off the main thread.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
        Self.receiveCloudKitShare(cloudKitShareMetadata, into: OneCartAppComposition.shareInbox)
    }

    /// UIKit creates the delegates, so they cannot take the inbox in `init`; they reach the one
    /// the composition root built and the session drains.
    static func receiveCloudKitShare(_ metadata: CKShare.Metadata, into inbox: any PendingShareInbox) {
        inbox.enqueue(PendingShareInvitation(metadata: metadata))
        NotificationCenter.default.post(name: .oneCartDidReceiveCloudKitShare, object: nil)
    }

    static func enqueuePendingShare(from options: UIScene.ConnectionOptions, into inbox: any PendingShareInbox) {
        guard let metadata = options.cloudKitShareMetadata else { return }
        inbox.enqueue(PendingShareInvitation(metadata: metadata))
    }
}
