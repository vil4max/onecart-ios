import AppIntents
import SwiftUI
import WidgetKit

// The Home Screen families share the cart screen's vocabulary: the category tile of
// `CartCategoryThumbnail`, the check control of `ProductPurchaseToggle` and the progress
// line of `CartProgressAccessory`. Colors come from the snapshot's accent and scheme so a
// theme override in the snapshot still wins over the system appearance.

func toggleAccessibilityLabel(for item: WidgetItemSnapshot) -> Text {
    item.isPurchased
        ? Text("widget.toggle_unmark_a11y \(item.name)")
        : Text("widget.toggle_mark_a11y \(item.name)")
}

/// Accented and vibrant rendering keep only the alpha of every color, so an opaque
/// fill behind a label would swallow it. Outside full color the fill becomes a wash.
struct WidgetBadgeFill: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let color: Color
    let shape: AnyShape

    func body(content: Content) -> some View {
        content
            .background(color.opacity(renderingMode == .fullColor ? 1 : 0.2), in: shape)
            .widgetAccentable()
    }
}

extension View {
    func widgetBadge(_ color: Color, in shape: some Shape) -> some View {
        modifier(WidgetBadgeFill(color: color, shape: AnyShape(shape)))
    }
}

struct WidgetCategoryThumbnail: View {
    @Environment(\.colorScheme) private var scheme
    let category: ProductCategory
    let accent: AppAccentColor
    let isDimmed: Bool
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: category.symbolName)
            // The cart tile draws a 16 pt symbol on 36 pt; keep that ratio at widget sizes.
            .font(.system(size: (size * 0.45).rounded(), weight: .semibold))
            .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
            .frame(width: size, height: size)
            .widgetBadge(
                OneCartPalette.primarySoft(for: scheme, accent: accent),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .opacity(isDimmed ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

struct WidgetPurchaseToggle: View {
    @Environment(\.colorScheme) private var scheme
    let item: WidgetItemSnapshot
    let snapshot: WidgetCartSnapshot
    let accent: AppAccentColor
    var font: Font = .title3

    var body: some View {
        Button(intent: ToggleProductPurchasedIntent(
            productID: item.id.uuidString,
            accountID: snapshot.accountID?.uuidString ?? "",
            familyID: snapshot.familyID?.uuidString ?? "",
            isPurchased: !item.isPurchased
        )) {
            Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                .font(font)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    item.isPurchased
                        ? OneCartPalette.primary(for: scheme, accent: accent)
                        : Color.secondary.opacity(0.5)
                )
                .widgetAccentable(item.isPurchased)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toggleAccessibilityLabel(for: item))
        .accessibilityAddTraits(item.isPurchased ? [.isSelected] : [])
        .disabled(snapshot.accountID == nil || snapshot.familyID == nil)
    }
}

/// One cart line as the app draws it: category tile, name struck through once completed,
/// and the check control at the trailing edge.
struct WidgetItemRow: View {
    let item: WidgetItemSnapshot
    let snapshot: WidgetCartSnapshot
    let accent: AppAccentColor
    var thumbnailSize: CGFloat = 24
    var nameFont: Font = .footnote
    var toggleFont: Font = .title3
    var showsSubtitle = false

    var body: some View {
        HStack(spacing: 8) {
            WidgetCategoryThumbnail(
                category: item.category,
                accent: accent,
                isDimmed: item.isPurchased,
                size: thumbnailSize
            )

            Text(item.name)
                .font(nameFont)
                .strikethrough(item.isPurchased)
                .foregroundStyle(item.isPurchased ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if showsSubtitle, let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            WidgetPurchaseToggle(item: item, snapshot: snapshot, accent: accent, font: toggleFont)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Trip progress as the tab bar accessory shows it: symbol, "N of M completed" and the bar;
/// the compact form drops the word like the accessory does once the tab bar minimizes.
struct WidgetProgressLine: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetCartSnapshot
    let accent: AppAccentColor
    var isCompact = false
    /// Who is shopping right now, shown at the trailing end of the label row.
    var partnerName: String?

    private var labelFont: Font {
        isCompact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: snapshot.isAllPurchased ? "checkmark.seal.fill" : "cart")
                    .font(labelFont)
                    .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                    .widgetAccentable()
                    .accessibilityHidden(true)

                Group {
                    if snapshot.isAllPurchased {
                        Text("widget.all_purchased")
                    } else if isCompact {
                        Text("cart.progress_compact \(snapshot.purchasedCount) \(snapshot.totalCount)")
                    } else {
                        Text("cart.progress_completed \(snapshot.purchasedCount) \(snapshot.totalCount)")
                    }
                }
                .font(labelFont)
                .monospacedDigit()

                if let partnerName, !partnerName.isEmpty {
                    Spacer(minLength: 4)
                    Text(partnerName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                        .layoutPriority(-1)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            ProgressView(value: snapshot.progress)
                .tint(OneCartPalette.primary(for: scheme, accent: accent))
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The cart glyph on a filled accent tile that heads the medium and large families.
struct WidgetCartTile: View {
    @Environment(\.colorScheme) private var scheme
    let accent: AppAccentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "cart.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .widgetBadge(
                OneCartPalette.primary(for: scheme, accent: accent),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

struct WidgetPartnerChip: View {
    @Environment(\.colorScheme) private var scheme
    let name: String
    let accent: AppAccentColor

    var body: some View {
        Text(name)
            .font(.caption2.weight(.medium))
            .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .widgetBadge(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
    }
}

/// Mirrors the cart's empty `ContentUnavailableView`: the same symbol over the caption.
struct WidgetEmptyState: View {
    var symbolFont: Font = .title2
    var showsCaption = true

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "cart.badge.plus")
                .font(symbolFont)
                .foregroundStyle(.tertiary)
            if showsCaption {
                Text("widget.empty")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
