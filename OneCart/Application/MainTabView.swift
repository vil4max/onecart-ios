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
            Tab("cart.tab", systemImage: "cart.fill", value: .cart) {
                HomeView(model: model)
            }
            Tab("history.tab", systemImage: "clock", value: .history) {
                HistoryView()
            }
            Tab("account.tab", systemImage: "person.crop.circle.fill", value: .account) {
                AccountView(model: model)
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
