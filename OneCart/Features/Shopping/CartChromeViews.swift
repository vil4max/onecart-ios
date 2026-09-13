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
    let title: LocalizedStringKey
    let message: LocalizedStringKey

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
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 8)),
                removal: .opacity
            )
        )
    }
}

struct CartProgressStrip: View {
    let isAllPurchased: Bool
    let purchasedCount: Int
    let totalCount: Int
    let familyMembersCount: Int
    let onManageFamily: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if isAllPurchased {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(OneCartPalette.primaryAccent)
                        Text("cart.all_purchased_title")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneCartPalette.primaryAccent)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Text("cart.progress_completed \(purchasedCount) \(totalCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                Spacer(minLength: 8)

                if familyMembersCount >= 2 {
                    Button(action: onManageFamily) {
                        Text("cart.together \(familyMembersCount)")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OneCartPalette.primaryAccent)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: isAllPurchased)

            ProgressView(
                value: Double(purchasedCount),
                total: Double(max(totalCount, 1))
            )
            .tint(OneCartPalette.primary)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: purchasedCount)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneCartPalette.background)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: isAllPurchased)
    }
}

struct ContentUnavailableViewCompat: View {
    let image: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

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
