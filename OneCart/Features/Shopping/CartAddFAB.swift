import SwiftUI

struct CartAddFAB: View {
    @Environment(\.colorScheme) private var colorScheme
    var accent: AppAccentColor?
    let action: () -> Void

    init(accent: AppAccentColor? = nil, action: @escaping () -> Void) {
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(OneCartPalette.primary(for: colorScheme, accent: accent), in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "cart.add_a11y"))
        .animation(.easeInOut(duration: 0.35), value: accent)
    }
}
