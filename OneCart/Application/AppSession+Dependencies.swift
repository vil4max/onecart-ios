import Foundation

/// The injected collaborators the session uses as they are, read from its one
/// `AppSessionDependencies` value.
extension AppSession {
    var persistence: PersistenceController {
        dependencies.persistence
    }

    var preferences: DevicePreferences {
        dependencies.preferences
    }

    var defaults: UserDefaults {
        dependencies.defaults
    }

    var clock: AppClock {
        dependencies.clock
    }

    var cloudSharing: any FamilyCloudSharing {
        dependencies.cloudSharing
    }

    var cloudUserIdentity: any CloudUserIdentifying {
        dependencies.cloudUserIdentity
    }

    var shareStore: any CloudKitShareStoring {
        dependencies.shareStore
    }

    var shareInbox: any PendingShareInbox {
        dependencies.shareInbox
    }

    var shareAccepter: any ShareInvitationAccepting {
        dependencies.shareAccepter
    }

    var appleSignIn: any AppleSignInAuthenticating {
        dependencies.appleSignIn
    }

    var categoryClassifier: any CategoryClassifying {
        dependencies.categoryClassifier
    }

    var widgetStore: any WidgetSnapshotStoring {
        dependencies.widgetStore
    }

    var activityNotifier: any CartActivityNotifying {
        dependencies.activityNotifier
    }

    var memberJoinNotifier: any MemberJoinNotifying {
        dependencies.memberJoinNotifier
    }

    var accountCloudDataDeleter: any AccountCloudDataDeleting {
        dependencies.accountCloudDataDeleter
    }

    var accountLocalStorePreparer: any AccountLocalStorePreparing {
        dependencies.accountLocalStorePreparer
    }
}
