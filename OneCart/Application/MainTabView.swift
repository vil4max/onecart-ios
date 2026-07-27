import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            HomeView(model: model)
                .tabItem {
                    Label("Корзина", systemImage: "cart.fill")
                }

            HistoryView()
                .tabItem {
                    Label("История", systemImage: "clock")
                }

            MoreView()
                .tabItem {
                    Label("Ещё", systemImage: "ellipsis.circle")
                }
        }
    }
}
