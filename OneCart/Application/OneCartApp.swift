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

    private static func makeModel() -> AppModel {
        #if DEBUG
            if DemoUIMode.isEnabled {
                return DemoUIMode.makeSession()
            }
        #endif
        return AppModel()
    }
}

private struct OneCartScene: View {
    @ObservedObject var model: AppModel

    var body: some View {
        RootView()
            .environmentObject(model)
            .preferredColorScheme(nil)
            .task {
                guard !Self.isRunningUnitTests else { return }
                await model.start()
                #if DEBUG
                    if DemoUIMode.isEnabled {
                        await DemoUIMode.seed(model)
                    }
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .oneCartDidReceiveCloudKitShare)) { _ in
                guard !Self.isRunningUnitTests else { return }
                Task { await model.acceptPendingCloudKitShares() }
            }
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
