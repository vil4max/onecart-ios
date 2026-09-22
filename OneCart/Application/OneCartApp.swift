import SwiftUI

@main
struct OneCartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = OneCartAppComposition.session

    var body: some Scene {
        WindowGroup {
            OneCartScene(model: model)
                .environment(
                    \.managedObjectContext,
                    model.persistence.container.viewContext
                )
        }
    }
}

@MainActor
enum OneCartAppComposition {
    static let session: AppSession = {
        #if DEBUG
            if DemoUIMode.isEnabled {
                return DemoUIMode.makeSession()
            }
        #endif
        return AppSession()
    }()
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
            .environment(\.locale, preferences.effectiveLocale)
            .task {
                guard !Self.isRunningUnitTests else { return }
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
                guard !Self.isRunningUnitTests else { return }
                guard newPhase == .active, model.account != nil else { return }
                Task {
                    await model.start()
                    await model.drainWidgetPendingToggles()
                    await model.syncCart(reason: .foreground)
                    model.updateWidgetSnapshot()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .oneCartDidReceiveCloudKitShare)) { _ in
                guard !Self.isRunningUnitTests else { return }
                Task { await model.acceptPendingCloudKitShares() }
            }
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @MainActor
    private static var bootstrapTask: Task<Void, Never>?
}
