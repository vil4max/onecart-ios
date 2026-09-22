import SwiftUI

/// Trip progress in the tab bar accessory: a label with a bar above the tab bar, a single
/// line once the bar minimizes on scroll and the accessory moves inline.
struct CartProgressAccessory: View {
    let viewModel: CartViewModel

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            // The accessory's height is fixed by the tab bar, so at accessibility sizes the
            // bar would be clipped; the label alone already carries the same information.
            if placement == .inline || dynamicTypeSize.isAccessibilitySize {
                compactContent
            } else {
                expandedContent
            }
        }
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: viewModel.purchasedCount)
    }

    private var symbolName: String {
        viewModel.isAllPurchased ? "checkmark.seal.fill" : "cart"
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            ProgressView(value: viewModel.progressFraction)
                .tint(OneCartPalette.primary)
        }
        .padding(.horizontal, 16)
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
                .accessibilityHidden(true)
            Text("cart.progress_compact \(viewModel.purchasedCount) \(viewModel.totalCount)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
    }
}
