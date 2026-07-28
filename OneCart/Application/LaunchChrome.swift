import SwiftUI

struct LaunchCartRideView: View {
    @EnvironmentObject private var model: AppModel

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            Image("LaunchIcon")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "common.loading"))
        .task {
            guard await waitUntilAppReady() else { return }
            onFinished()
        }
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
