import SwiftUI

struct CartBusyOverlay: View {
    var messageKey: LocalizedStringKey = "cart.updating"

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(OneCartPalette.primary)
                Text(messageKey)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(messageKey))
    }
}

struct ReadOnlyBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("cart.read_only_title")
                    .font(.subheadline.bold())
                Text("cart.read_only_message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.read_only")
    }
}

struct CartAllPurchasedHeroCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
                .accessibilityHidden(true)

            Text("cart.all_purchased_title")
                .font(.headline)
                .foregroundStyle(OneCartPalette.primaryAccent)

            Text("cart.all_purchased_subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.all_purchased")
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94)),
                removal: .opacity
            )
        )
    }
}
