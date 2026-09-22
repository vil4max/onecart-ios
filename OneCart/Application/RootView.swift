import SwiftUI
import UIKit

private enum RootPhase: Equatable {
    case loading
    case welcome
    case main
}

/// Resolves the session from the environment; `RootSessionView` owns everything built from it.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        RootSessionView(session: session)
    }
}

/// The screen boundary for Welcome: creates its ViewModel once and switches between
/// loading, Welcome and the main tabs. Screens never see the session itself.
private struct RootSessionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cart overlay stays up until the ride ends; only then the real UI mounts.
    @State private var cartRideFinished = false
    @State private var welcomeViewModel: WelcomeViewModel
    @State private var namePromptViewModel: MemberNamePromptViewModel

    private let session: AppSession
    private let state: any SessionStateReading
    private let alerts: any AlertPresenting

    init(session: AppSession) {
        self.session = session
        state = session
        alerts = session
        _welcomeViewModel = State(initialValue: WelcomeViewModel(session: session))
        _namePromptViewModel = State(initialValue: MemberNamePromptViewModel(prompting: session))
    }

    private var isNamePromptPresented: Binding<Bool> {
        Binding(
            get: { cartRideFinished && phase == .main && namePromptViewModel.isPresented },
            set: { presented in
                if !presented {
                    namePromptViewModel.handleDismissal()
                }
            }
        )
    }

    private var phase: RootPhase {
        if !state.isReady {
            return .loading
        }
        if state.needsWelcome || state.account == nil {
            return .welcome
        }
        return .main
    }

    var body: some View {
        ZStack {
            ZStack {
                if cartRideFinished {
                    destinationView
                        .transition(.opacity)
                } else {
                    OneCartPalette.primary(accent: state.preferences.accentColor).ignoresSafeArea()
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.4),
                value: cartRideFinished
            )

            if !cartRideFinished {
                LaunchCartRideView {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                        cartRideFinished = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(4)
            }
        }
        .alert(
            alerts.userAlert?.kind.title ?? "",
            isPresented: Binding(
                get: { alerts.userAlert != nil },
                set: {
                    if !$0 {
                        alerts.dismissAlert()
                    }
                }
            )
        ) {
            Button("common.ok", role: .cancel) {
                alerts.dismissAlert()
            }
        } message: {
            Text(alerts.userAlert?.message ?? "")
        }
        .sheet(isPresented: isNamePromptPresented) {
            MemberNamePromptView(viewModel: namePromptViewModel)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch phase {
        case .loading:
            OneCartPalette.primary(accent: state.preferences.accentColor).ignoresSafeArea()
        case .welcome:
            WelcomeView(viewModel: welcomeViewModel)
        case .main:
            MainTabView(session: session)
                .id(state.preferences.language)
        }
    }
}
