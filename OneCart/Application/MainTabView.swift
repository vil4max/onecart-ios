import SwiftUI

enum MainTab: String, Hashable {
    case cart
    case history
    case account
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: MainTab = Self.initialTab

    var body: some View {
        TabView(selection: $selection) {
            HomeView(model: model)
                .tag(MainTab.cart)
                .tabItem {
                    Label("Корзина", systemImage: "cart.fill")
                }

            HistoryView()
                .tag(MainTab.history)
                .tabItem {
                    Label("История", systemImage: "clock")
                }

            AccountView(model: model)
                .tag(MainTab.account)
                .tabItem {
                    Label("Аккаунт", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(OneCartPalette.primary)
        .onReceive(model.$preferredMainTab.compactMap { $0 }) { tab in
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
