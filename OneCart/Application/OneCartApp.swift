import SwiftUI

@main
struct OneCartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = OneCartApp.makeModel()

    var body: some Scene {
        WindowGroup {
            OneCartScene(model: model)
                .environment(
                    \.managedObjectContext,
                    model.persistence.container.viewContext
                )
        }
    }

    private static func makeModel() -> AppSession {
        #if DEBUG
            if DemoUIMode.isEnabled {
                return DemoUIMode.makeSession()
            }
        #endif
        return AppSession()
    }
}

private struct OneCartScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: AppSession

    var body: some View {
        RootView()
            .environmentObject(model)
            .preferredColorScheme(nil)
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
                Task { await model.syncCart(reason: .foreground) }
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
