import SwiftUI
import UIKit

private enum RootPhase: Equatable {
    case loading
    case welcome
    case main
}

struct RootView: View {
    @EnvironmentObject private var model: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cart overlay stays up until the ride ends; only then the real UI mounts.
    @State private var cartRideFinished = false

    private var phase: RootPhase {
        if !model.isReady {
            return .loading
        }
        if model.needsWelcome || model.account == nil {
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
                    Color("LaunchBackground").ignoresSafeArea()
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
            model.userAlert?.kind.title ?? "",
            isPresented: Binding(
                get: { model.userAlert != nil },
                set: {
                    if !$0 {
                        model.dismissAlert()
                    }
                }
            )
        ) {
            Button("common.ok", role: .cancel) {
                model.dismissAlert()
            }
        } message: {
            Text(model.userAlert?.message ?? "")
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch phase {
        case .loading:
            Color("LaunchBackground").ignoresSafeArea()
        case .welcome:
            WelcomeView(model: model)
        case .main:
            MainTabView()
        }
    }
}
