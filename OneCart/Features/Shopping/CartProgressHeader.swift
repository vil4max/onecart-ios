import SwiftUI

/// Trip progress at the top of the cart: "N of M completed" with a bar, or the all-bought
/// title once every line is checked.
struct CartProgressHeader: View {
    let viewModel: CartViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

            ProgressView(value: viewModel.progressFraction)
                .tint(OneCartPalette.primary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cart.progress")
        .animation(.snappy, value: viewModel.purchasedCount)
    }

    private var symbolName: String {
        viewModel.isAllPurchased ? "checkmark.seal.fill" : "cart"
    }
}
