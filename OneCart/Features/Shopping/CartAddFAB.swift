import SwiftUI

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
                .rotationEffect(.degrees(isComposing ? 45 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isComposing)
                .frame(width: 40, height: 40)
        }
        // System glass supplies the press response, shadow and legibility over list content.
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(OneCartPalette.primary(for: colorScheme, accent: accent))
        .accessibilityLabel(Text(isComposing ? "common.cancel" : "cart.add_a11y"))
        .animation(.easeInOut(duration: 0.35), value: accent)
    }
}
