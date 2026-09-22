import SwiftUI

enum MainTab: String, Hashable {
    case cart
    case history
    case account
}

/// The screen boundary for the three tabs: creates each ViewModel once from the session.
struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: MainTab = Self.initialTab
    @State private var cartViewModel: CartViewModel
    @State private var historyViewModel: HistoryViewModel
    @State private var accountViewModel: AccountViewModel

    private let state: any SessionStateReading
    private let tabs: any MainTabRouting

    init(session: AppSession) {
        state = session
        tabs = session
        _cartViewModel = State(initialValue: CartViewModel(session: session))
        _historyViewModel = State(initialValue: HistoryViewModel(history: session))
        _accountViewModel = State(initialValue: AccountViewModel(session: session))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("cart.tab", systemImage: "cart.fill", value: .cart) {
                HomeView(viewModel: cartViewModel)
            }
            Tab("history.tab", systemImage: "clock", value: .history) {
                HistoryView(viewModel: historyViewModel)
            }
            Tab("account.tab", systemImage: "gearshape.fill", value: .account) {
                AccountView(viewModel: accountViewModel)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(OneCartPalette.primary(for: colorScheme, accent: state.preferences.accentColor))
        .animation(.easeInOut(duration: 0.35), value: state.preferences.accentColor)
        .onChange(of: tabs.preferredMainTab, initial: true) { _, tab in
            guard let tab else { return }
            selection = tab
            tabs.clearPreferredMainTab()
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
