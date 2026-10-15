import Foundation

/// Every collaborator `AppSession` does not build from the others. Nothing here has a default:
/// `OneCartAppComposition` builds the production graph, the DEBUG demo builds its own through
/// the same type, and the test session builders pass fakes, so no session reaches a live
/// singleton it was not handed.
@MainActor
struct AppSessionDependencies {
    let persistence: PersistenceController
    let preferences: DevicePreferences
    let defaults: UserDefaults
    let cloudSharing: any FamilyCloudSharing
    /// The container seam the share code and the session's share lookups use.
    let shareStore: any CloudKitShareStoring
    let recordPermissions: any RecordPermissionChecking
    let appleSignIn: any AppleSignInAuthenticating
    let accountCloudDataDeleter: any AccountCloudDataDeleting
    let accountLocalStorePreparer: any AccountLocalStorePreparing
    let widgetStore: any WidgetSnapshotStoring
    let categoryClassifier: any CategoryClassifying
    let cloudUserIdentity: any CloudUserIdentifying
    let shoppingTripBackend: any ShoppingTripActivityBackend
    let shareInbox: any PendingShareInbox
    let shareAccepter: any ShareInvitationAccepting
    let activityNotifier: any CartActivityNotifying
    let memberJoinNotifier: any MemberJoinNotifying
    let connectivity: any ConnectivityMonitoring
    let clock: AppClock
}
