import SwiftUI
import UIKit

enum OneCartPalette {
    /// Filled surfaces that carry white content.
    static let primary = adaptive(light: (52, 120, 91), dark: (62, 147, 112))
    /// Pressed state of a filled surface.
    static let primaryStrong = adaptive(light: (40, 95, 71), dark: (46, 110, 83))
    /// Text and glyphs drawn on `background`, `surface` or `primarySoft`.
    static let primaryAccent = adaptive(light: (40, 95, 71), dark: (116, 199, 159))
    /// Tinted backing for chips and icon tiles.
    static let primarySoft = adaptive(light: (225, 239, 231), dark: (30, 51, 41))
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let danger = adaptive(light: (185, 74, 72), dark: (232, 117, 111))

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: components.0 / 255,
                green: components.1 / 255,
                blue: components.2 / 255,
                alpha: 1
            )
        })
    }
}

private enum RootPhase: Equatable {
    case loading
    case welcome
    case main
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
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
                set: { if !$0 { model.dismissAlert() } }
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
