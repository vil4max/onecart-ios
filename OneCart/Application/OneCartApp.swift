import SwiftUI

@main
struct OneCartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

@MainActor
enum OneCartAppComposition {
    #if DEBUG
        private(set) static var didBuildSession = false
    #endif

    static let session: AppSession = {
        #if DEBUG
            didBuildSession = true
            if DemoUIMode.isEnabled {
                return DemoUIMode.makeSession()
            }
        #endif
        return AppSession()
    }()
}

private struct OneCartRootScene: View {
    @State private var model = OneCartAppComposition.session

    var body: some View {
        OneCartScene(model: model)
            .environment(
                \.managedObjectContext,
                model.persistence.container.viewContext
            )
    }
}

private struct OneCartScene: View {
    @Environment(\.scenePhase) private var scenePhase
    let model: AppSession

    private var preferences: DevicePreferences {
        model.preferences
    }

    var body: some View {
        RootView()
            .environment(model)
            .preferredColorScheme(preferences.theme.colorScheme)
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
