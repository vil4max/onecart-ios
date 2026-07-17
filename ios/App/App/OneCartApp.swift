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
                await model.start()
            }
            .onOpenURL { url in
                Task { await model.handleIncomingURL(url) }
            }
    }
}
