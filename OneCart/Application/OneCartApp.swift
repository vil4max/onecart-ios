import SwiftUI

@main
struct OneCartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

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

private struct OneCartScene: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: DevicePreferences

    init(model: AppModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        RootView()
            .environmentObject(model)
            .preferredColorScheme(preferences.theme.colorScheme)
            .task {
                guard !Self.isRunningUnitTests else { return }
                await model.start()
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
