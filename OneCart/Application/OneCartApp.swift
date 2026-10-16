import AppIntents
import SwiftUI
import UserNotifications

@main
struct OneCartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Registers the session for the intents' `@Dependency` at launch, before the system can
    /// perform an intent; a Live Activity intent launches this process in the background. The
    /// provider is lazy: the session is built on first use by the scene or an intent, never in
    /// `App.init`, which also runs for background launches that need neither.
    init() {
        guard !TestHost.isRunningUnitTests else { return }
        AppDependencyManager.shared.add(dependency: { @Sendable () async -> any CartIntentHandling in
            await MainActor.run { OneCartAppComposition.session.intentHandler }
        })
    }

    var body: some Scene {
        WindowGroup {
            // The unit-test host never builds the production session: tests build their own
            // over isolated stores, and the real one would touch ActivityKit and the App Group.
            if TestHost.isRunningUnitTests {
                Color.clear
            } else {
                OneCartRootScene()
            }
        }
    }
}

/// UI tests launch the app in a separate process without this variable, so only the unit-test
/// host is affected.
enum TestHost {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// The one place that builds live services. Everything below it takes its collaborators in
/// `init`; only the UIKit delegates, which UIKit creates, read `shareInbox` from here.
@MainActor
enum OneCartAppComposition {
    #if DEBUG
        private(set) static var didBuildSession = false
    #endif

    /// Filled by the delegates, drained by the session.
    static let shareInbox: any PendingShareInbox = LivePendingShareInbox()

    static let session: AppSession = {
        // Tests build their own sessions over isolated stores. Trapping here fails the whole
        // run whichever test reaches the production session, independent of test order.
        precondition(!TestHost.isRunningUnitTests, "The unit-test host must never build the app session")
        #if DEBUG
            didBuildSession = true
            if DemoUIMode.isEnabled {
                return DemoUIMode.makeSession()
            }
        #endif
        return AppSession(live())
    }()

    /// The production graph: the real stores, App Group, Keychain, iCloud, ActivityKit and
    /// notification center.
    static func live() -> AppSessionDependencies {
        let defaults = UserDefaults.standard
        return dependencies(
            persistence: .shared,
            preferences: DevicePreferences(defaults: defaults, appGroupDefaults: OneCartAppGroup.defaults),
            defaults: defaults,
            appleSignIn: AppleSignInService.shared,
            cloudSharing: nil
        )
    }

    /// The thumbnail reads the stored accent when a share is stamped, not the launch accent.
    private static func shareThumbnail(readingAccentFrom defaults: UserDefaults) -> ShareThumbnailRenderer {
        // UserDefaults is documented as thread-safe; the SDK just does not mark it Sendable.
        nonisolated(unsafe) let accentDefaults = defaults
        return ShareThumbnailRenderer(currentAccent: {
            AppAccentColor(storedRawValue: accentDefaults.string(forKey: OneCartAppGroup.accentColorKey))
        })
    }

    /// The live graph over the given store, defaults and sign-in. `cloudSharing` nil builds the
    /// CloudKit backend; the DEBUG demo passes its own pieces through here, so it builds the
    /// session through the same initializer as production.
    static func dependencies(
        persistence: PersistenceController,
        preferences: DevicePreferences,
        defaults: UserDefaults,
        appleSignIn: any AppleSignInAuthenticating,
        cloudSharing: (any FamilyCloudSharing)?
    ) -> AppSessionDependencies {
        let clock = AppClock.live
        let cloudContainer = LazyCloudContainer()
        let shareStore = LiveCloudKitShareStore(
            persistence: persistence,
            cloudContainer: cloudContainer,
            shareThumbnail: shareThumbnail(readingAccentFrom: defaults)
        )
        let cloudSharing =
            cloudSharing
            ?? CloudKitBackendService(
                persistence: persistence,
                cloudContainer: cloudContainer,
                shareStore: shareStore,
                clock: clock
            )
        let notificationCenter = UNUserNotificationCenter.current()
        return AppSessionDependencies(
            persistence: persistence,
            preferences: preferences,
            defaults: defaults,
            cloudSharing: cloudSharing,
            shareStore: shareStore,
            recordPermissions: ContainerRecordPermissions(persistence: persistence),
            appleSignIn: appleSignIn,
            accountCloudDataDeleter: cloudSharing,
            accountLocalStorePreparer: persistence,
            widgetStore: WidgetSnapshotStore.shared,
            categoryClassifier: CompositeCategoryClassifier.live(),
            cloudUserIdentity: cloudSharing,
            shoppingTripBackend: LiveShoppingTripActivityBackend(),
            shareInbox: shareInbox,
            shareAccepter: persistence,
            activityNotifier: LiveCartActivityNotifier(defaults: defaults, notificationCenter: notificationCenter),
            memberJoinNotifier: LiveMemberJoinNotifier(defaults: defaults, notificationCenter: notificationCenter),
            connectivity: ConnectivityMonitor(),
            clock: clock
        )
    }
}

private struct OneCartRootScene: View {
    @State private var model = OneCartAppComposition.session

    private static let demoLaunchOptions: DemoLaunchOptions = {
        #if DEBUG
            DemoLaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
            .none
        #endif
    }()

    var body: some View {
        OneCartScene(model: model)
            .environment(
                \.managedObjectContext,
                model.persistence.container.viewContext
            )
            .environment(\.demoLaunchOptions, Self.demoLaunchOptions)
    }
}

private struct OneCartScene: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: AppSession

    var body: some View {
        RootView()
            .environment(model)
            .task {
                if Self.bootstrapTask == nil {
                    Self.bootstrapTask = Task { @MainActor in
                        await model.start()
                        #if DEBUG
                            if DemoUIMode.isEnabled {
                                await DemoUIMode.seed(model)
                            }
                        #endif
                    }
                }
                await Self.bootstrapTask?.value
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, model.account != nil else { return }
                Task {
                    await model.start()
                    await model.drainWidgetPendingToggles()
                    await model.syncCart(reason: .foreground)
                    model.updateWidgetSnapshot()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .oneCartDidReceiveCloudKitShare)) { _ in
                Task { await model.acceptPendingCloudKitShares() }
            }
    }

    @MainActor
    private static var bootstrapTask: Task<Void, Never>?
}
