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
            .background(
                OneCartPalette.surface,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(messageKey))
    }
}

struct ReadOnlyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("cart.read_only_title")
                    .font(.subheadline.bold())
                Text("cart.read_only_message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .oneCartCard()
    }
}

struct EmptyCard: View {
    let image: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: image)
                .font(.system(size: 28))
                .foregroundColor(OneCartPalette.primary)
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
        .padding(18)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

struct ContentUnavailableViewCompat: View {
    let image: String
    let title: String
    let message: String

    var body: some View {
        EmptyCard(image: image, title: title, message: message)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneCartPalette.background)
    }
}

extension View {
    func oneCartMediumSheet() -> some View {
        presentationDetents([.medium])
            .presentationDragIndicator(.visible)
    }
}
