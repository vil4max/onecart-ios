import SwiftUI

enum MainTab: String, Hashable {
    case cart
    case history
    case account
}

struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppSession.self) private var model
    @State private var selection: MainTab = Self.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("cart.tab", systemImage: "cart.fill", value: .cart) {
                HomeView(model: model)
            }
            Tab("history.tab", systemImage: "clock", value: .history) {
                HistoryView()
            }
            Tab("account.tab", systemImage: "gearshape.fill", value: .account) {
                AccountView(model: model)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(OneCartPalette.primary(for: colorScheme, accent: model.preferences.accentColor))
        .animation(.easeInOut(duration: 0.35), value: model.preferences.accentColor)
        .onChange(of: model.preferredMainTab, initial: true) { _, tab in
            guard let tab else { return }
            selection = tab
            model.preferredMainTab = nil
        }
    }

    private static var initialTab: MainTab {
        #if DEBUG
            return DemoUIMode.initialTab ?? .cart
        #else
            return .cart
        #endif
    }
}
