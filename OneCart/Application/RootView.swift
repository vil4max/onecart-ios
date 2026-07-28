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
        ZStack(alignment: .bottom) {
            ZStack {
                if cartRideFinished {
                    destinationView
                        .transition(.opacity)
                } else {
                    OneCartPalette.background.ignoresSafeArea()
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
                .transition(.opacity)
                .zIndex(4)
            }
        }
        .alert(
            "common.app_name",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.dismissAlert() } }
            )
        ) {
            Button("common.ok", role: .cancel) {
                model.dismissAlert()
            }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch phase {
        case .loading:
            OneCartPalette.background.ignoresSafeArea()
        case .welcome:
            WelcomeView(model: model)
        case .main:
            MainTabView()
        }
    }
}

/// Lightweight cart ride on a solid background. Destination UI mounts only after
/// this finishes, so the heavy main screen is not animating under an opaque veil.
private struct LaunchCartRideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    /// Only `travel` is animated — keeps the ride smooth on the main thread.
    @State private var travel: CGFloat = -1.15

    private let driveInDuration: Double = 0.9
    private let driveOutDuration: Double = 0.55
    private let cartWidth: CGFloat = 92

    var body: some View {
        GeometryReader { geo in
            let travelX = travel * (geo.size.width * 0.8)

            ZStack {
                OneCartPalette.background.ignoresSafeArea()

                Image("LaunchCart")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: cartWidth)
                    .offset(x: travelX)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "common.loading"))
        .accessibilityAddTraits(.updatesFrequently)
        .task { await runRide() }
    }

    @MainActor
    private func runRide() async {
        if reduceMotion {
            travel = 0
            guard await waitUntilAppReady() else { return }
            onFinished()
            return
        }

        withAnimation(.timingCurve(0.2, 0.82, 0.24, 1, duration: driveInDuration)) {
            travel = 0
        }
        do {
            try await Task.sleep(nanoseconds: UInt64(driveInDuration * 1_000_000_000))
        } catch {
            return
        }

        guard await waitUntilAppReady() else { return }

        withAnimation(.timingCurve(0.4, 0.02, 0.2, 1, duration: driveOutDuration)) {
            travel = 1.35
        }
        do {
            try await Task.sleep(nanoseconds: UInt64((driveOutDuration + 0.03) * 1_000_000_000))
        } catch {
            onFinished()
            return
        }
        onFinished()
    }

    @MainActor
    private func waitUntilAppReady() async -> Bool {
        if model.isReady { return true }
        for await ready in model.$isReady.values {
            if Task.isCancelled { return false }
            if ready { return true }
        }
        return false
    }
}

struct OneCartMark: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            Image(systemName: "cart.fill")
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: compact ? 36 : 40, height: compact ? 36 : 40)
                .background(
                    OneCartPalette.primary,
                    in: RoundedRectangle(cornerRadius: compact ? 11 : 12, style: .continuous)
                )
            Text("OneCart")
                .font(compact ? .title3.bold() : .title2.bold())
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OneCart")
    }
}

struct OneCartPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                configuration.isPressed
                    ? OneCartPalette.primaryStrong
                    : OneCartPalette.primary,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct OneCartSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(OneCartPalette.primaryAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                OneCartPalette.primarySoft.opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

extension View {
    func oneCartCard() -> some View {
        padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}
