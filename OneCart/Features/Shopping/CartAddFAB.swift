import SwiftUI

struct CartFABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct CartAddFAB: View {
    @Environment(\.colorScheme) private var colorScheme
    var accent: AppAccentColor?
    var isComposing: Bool
    let action: () -> Void

    init(
        accent: AppAccentColor? = nil,
        isComposing: Bool = false,
        action: @escaping () -> Void
    ) {
        self.accent = accent
        self.isComposing = isComposing
        self.action = action
    }

    var body: some View {
        Button {
            CartHaptics.light()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isComposing ? 45 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isComposing)
                .frame(width: 56, height: 56)
                .background(OneCartPalette.primary(for: colorScheme, accent: accent), in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(CartFABButtonStyle())
        .accessibilityLabel(String(localized: isComposing ? "common.cancel" : "cart.add_a11y"))
        .animation(.easeInOut(duration: 0.35), value: accent)
    }
}
