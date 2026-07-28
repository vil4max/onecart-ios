import SwiftUI

/// Lightweight cart ride on a solid background. Destination UI mounts only after
/// this finishes, so the heavy main screen is not animating under an opaque veil.
struct LaunchCartRideView: View {
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
