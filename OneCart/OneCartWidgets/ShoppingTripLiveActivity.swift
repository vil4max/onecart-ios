import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The shopping trip on the Lock Screen and in the Dynamic Island (REQ-WIDGET-040). It uses
/// the widget vocabulary: category tiles, the check control and the progress line. Checks
/// run `ToggleProductPurchasedIntent` in the app, which then updates this activity.
struct ShoppingTripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingTripAttributes.self) { context in
            ShoppingTripLockScreenView(attributes: context.attributes, state: context.state)
                .activitySystemActionForegroundColor(OneCartPalette.primary(accent: context.state.accentColor))
        } dynamicIsland: { context in
            let state = context.state
            let accent = state.accentColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ShoppingTripCartTile(accent: accent, size: 36)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ShoppingTripRemainingLabel(state: state, font: .headline)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.cartTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ShoppingTripExpandedBottom(attributes: context.attributes, state: state)
                }
            } compactLeading: {
                Image(systemName: "cart.fill")
                    .foregroundStyle(OneCartPalette.primaryAccent(for: .dark, accent: accent))
                    .accessibilityLabel(Text(state.cartTitle))
            } compactTrailing: {
                ShoppingTripRemainingLabel(state: state, font: .caption.weight(.semibold), isCompact: true)
            } minimal: {
                ShoppingTripProgressRing(state: state)
            }
            .keylineTint(OneCartPalette.primary(for: .dark, accent: accent))
        }
    }
}

// MARK: - Lock Screen

private struct ShoppingTripLockScreenView: View {
    @Environment(\.colorScheme) private var scheme
    let attributes: ShoppingTripAttributes
    let state: ShoppingTripAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ShoppingTripCartTile(accent: state.accentColor, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.cartTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    ShoppingTripProgressCaption(state: state)
                }
                Spacer(minLength: 8)
                ShoppingTripEndButton()
            }

            ShoppingTripProgressBar(state: state, tint: OneCartPalette.primary(for: scheme, accent: state.accentColor))

            if state.isAllPurchased {
                Label("widget.all_purchased", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: state.accentColor))
            } else {
                // Rows touch so each check target spans the whole row pitch without overlapping.
                VStack(spacing: 0) {
                    ForEach(state.nextItems) { item in
                        ShoppingTripItemRow(item: item, attributes: attributes, accent: state.accentColor)
                    }
                }
                ShoppingTripMoreCaption(state: state)
            }
        }
        .padding(16)
    }
}

// MARK: - Dynamic Island

private struct ShoppingTripExpandedBottom: View {
    let attributes: ShoppingTripAttributes
    let state: ShoppingTripAttributes.ContentState

    /// The expanded island is shorter than the Lock Screen; two lines keep it readable.
    private static let visibleItems = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShoppingTripProgressBar(state: state, tint: OneCartPalette.primary(for: .dark, accent: state.accentColor))

            if state.isAllPurchased {
                Label("widget.all_purchased", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
            } else {
                VStack(spacing: 0) {
                    ForEach(state.nextItems.prefix(Self.visibleItems)) { item in
                        ShoppingTripItemRow(item: item, attributes: attributes, accent: state.accentColor)
                    }
                }
            }

            HStack {
                ShoppingTripProgressCaption(state: state)
                Spacer(minLength: 8)
                ShoppingTripEndButton()
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct ShoppingTripProgressRing: View {
    /// 9 pt at the default text size, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var symbolSize: CGFloat = 9
    let state: ShoppingTripAttributes.ContentState

    var body: some View {
        Gauge(value: state.progress) {
            Image(systemName: "cart.fill")
        } currentValueLabel: {
            Image(systemName: state.isAllPurchased ? "checkmark" : "cart.fill")
                .font(.system(size: symbolSize, weight: .bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(OneCartPalette.primary(for: .dark, accent: state.accentColor))
        .accessibilityLabel(Text("cart.progress_compact \(state.purchasedCount) \(state.totalCount)"))
    }
}

// MARK: - Shared pieces

/// Minimum tap target (HIG: 44 pt).
private let shoppingTripTapTarget: CGFloat = 44

private struct ShoppingTripProgressBar: View {
    let state: ShoppingTripAttributes.ContentState
    let tint: Color

    var body: some View {
        ProgressView(value: state.progress)
            .tint(tint)
            .accessibilityLabel(Text("trip.progress_a11y"))
            .accessibilityValue(Text("cart.progress_completed \(state.purchasedCount) \(state.totalCount)"))
    }
}

private struct ShoppingTripItemRow: View {
    /// The row pitch the list had with 6 pt spacing; the check target fills it. Three rows at
    /// 44 pt would push the card past the 160 pt the Lock Screen shows without truncating.
    static let height: CGFloat = 30

    let item: ShoppingTripItem
    let attributes: ShoppingTripAttributes
    let accent: AppAccentColor

    var body: some View {
        HStack(spacing: 8) {
            WidgetCategoryThumbnail(category: item.category, accent: accent, isDimmed: false, size: 24)
            Text(item.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(intent: ToggleProductPurchasedIntent(
                productID: item.id.uuidString,
                accountID: attributes.accountID.uuidString,
                familyID: attributes.familyID.uuidString,
                isPurchased: true
            )) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: shoppingTripTapTarget, height: Self.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The wider target reaches into the card's trailing padding; the circle stays put.
            .padding(.trailing, -(shoppingTripTapTarget - 24) / 2)
            .accessibilityLabel(Text("widget.toggle_mark_a11y \(item.name)"))
        }
        .frame(minHeight: Self.height)
        .accessibilityElement(children: .contain)
    }
}

private struct ShoppingTripEndButton: View {
    var body: some View {
        Button(intent: EndShoppingTripIntent()) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
                .frame(width: shoppingTripTapTarget, height: shoppingTripTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A 44 pt target around the 28 pt circle; the layout keeps the circle's size.
        .padding(-(shoppingTripTapTarget - 28) / 2)
        .accessibilityLabel(Text("trip.end_button"))
    }
}

private struct ShoppingTripCartTile: View {
    let accent: AppAccentColor
    let size: CGFloat

    var body: some View {
        Image(systemName: "cart.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                OneCartPalette.primary(accent: accent),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// "N of M" under the title; the all-bought state reads from the label below instead.
private struct ShoppingTripProgressCaption: View {
    let state: ShoppingTripAttributes.ContentState

    var body: some View {
        Text("cart.progress_completed \(state.purchasedCount) \(state.totalCount)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

private struct ShoppingTripRemainingLabel: View {
    let state: ShoppingTripAttributes.ContentState
    let font: Font
    var isCompact = false

    var body: some View {
        Group {
            if state.isAllPurchased {
                Image(systemName: "checkmark")
                    .accessibilityLabel(Text("widget.all_purchased"))
            } else if isCompact {
                Text(state.remainingCount, format: .number)
                    .accessibilityLabel(Text("trip.remaining \(state.remainingCount)"))
            } else {
                Text("trip.remaining \(state.remainingCount)")
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(OneCartPalette.primaryAccent(for: .dark, accent: state.accentColor))
        .lineLimit(1)
    }
}

/// Lines to buy beyond the ones the activity lists.
private struct ShoppingTripMoreCaption: View {
    let state: ShoppingTripAttributes.ContentState

    var body: some View {
        let hidden = state.remainingCount - state.nextItems.count
        if hidden > 0 {
            Text("trip.more \(hidden)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
