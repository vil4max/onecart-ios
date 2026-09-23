import SwiftUI

/// Trip progress at the top of the cart: "N of M completed" with a bar, or the all-bought
/// title once every line is checked, plus the control that puts the trip on the Lock Screen.
struct CartProgressHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let viewModel: CartViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // At accessibility sizes the control moves under the progress so neither truncates.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    progressLabel
                    if viewModel.showsShoppingTripControl {
                        shoppingTripButton
                    }
                }
            } else {
                HStack(spacing: 6) {
                    progressLabel
                    if viewModel.showsShoppingTripControl {
                        Spacer(minLength: 8)
                        shoppingTripButton
                    }
                }
            }

            ProgressView(value: viewModel.progressFraction)
                .tint(OneCartPalette.primary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: viewModel.purchasedCount)
        .animation(.snappy, value: viewModel.isShoppingTripActive)
    }

    private var progressLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            if viewModel.isAllPurchased {
                Text("cart.all_purchased_title")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("cart.progress_completed \(viewModel.purchasedCount) \(viewModel.totalCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.progress")
    }

    /// Starts or stops the Live Activity (REQ-WIDGET-040, REQ-WIDGET-060).
    private var shoppingTripButton: some View {
        Button {
            Task { await viewModel.toggleShoppingTrip() }
        } label: {
            Label(
                viewModel.isShoppingTripActive ? "trip.end_button" : "trip.start_button",
                systemImage: viewModel.isShoppingTripActive ? "bag.fill" : "bag"
            )
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(OneCartPalette.primary)
        .accessibilityHint(Text("trip.control_hint"))
        .accessibilityIdentifier("cart.shoppingTrip")
    }

    private var symbolName: String {
        viewModel.isAllPurchased ? "checkmark.seal.fill" : "cart"
    }
}
