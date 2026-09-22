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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("cart.read_only_title")
                    .font(.subheadline.bold())
                Text("cart.read_only_message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyCard: View {
    let image: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: image)
                .font(.system(size: 28))
                .foregroundStyle(OneCartPalette.primary)
                .frame(width: 52, height: 52)
                .background(
                    OneCartPalette.primarySoft,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

struct CartAllPurchasedHeroCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(OneCartPalette.primarySoft)
                    .frame(width: 58, height: 58)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(OneCartPalette.primaryAccent)
            }
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("cart.all_purchased_title")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(OneCartPalette.primaryAccent)

                Text("cart.all_purchased_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 8)),
                removal: .opacity
            )
        )
    }
}
