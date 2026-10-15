import SwiftUI

enum MainTab: String, Hashable {
    case cart
    case history
    case account
}

/// The three tabs' ViewModels, built once by the owner of `MainTabView`: a `State` initial
/// value is evaluated on every view init, so building them inside the tab view would throw
/// away three ViewModels each time its parent re-renders.
@MainActor
struct MainTabViewModels {
    let cart: CartViewModel
    let history: HistoryViewModel
    let account: AccountViewModel

    init(session: AppSession) {
        cart = CartViewModel(session: session)
        history = HistoryViewModel(history: session)
        account = AccountViewModel(session: session)
    }
}

/// The screen boundary for the three tabs.
struct MainTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: MainTab = Self.initialTab

    private let cartViewModel: CartViewModel
    private let historyViewModel: HistoryViewModel
    private let accountViewModel: AccountViewModel
    private let state: any SessionStateReading
    private let tabs: any MainTabRouting

    init(session: AppSession, viewModels: MainTabViewModels) {
        state = session
        tabs = session
        cartViewModel = viewModels.cart
        historyViewModel = viewModels.history
        accountViewModel = viewModels.account
    }

    init(session: AppSession) {
        self.init(session: session, viewModels: MainTabViewModels(session: session))
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
