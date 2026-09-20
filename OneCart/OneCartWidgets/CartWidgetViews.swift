import AppIntents
import SwiftUI
import WidgetKit

struct CartWidgetRootView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CartWidgetEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineLockScreenWidgetView(snapshot: entry.snapshot)
        case .accessoryCircular:
            CircularLockScreenWidgetView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            RectangularLockScreenWidgetView(snapshot: entry.snapshot)
        case .systemSmall:
            SmallHomeWidgetView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumHomeWidgetView(snapshot: entry.snapshot)
        case .systemLarge, .systemExtraLarge:
            LargeHomeWidgetView(snapshot: entry.snapshot)
        // The iOS 27 SDK (Swift 6.4, Xcode 27) adds this case; GitHub Actions still builds
        // with Xcode 26.6, where it does not exist. Not in supportedFamilies.
        #if compiler(>=6.4)
            case .systemExtraLargePortrait:
                LargeHomeWidgetView(snapshot: entry.snapshot)
        #endif
        @unknown default:
            MediumHomeWidgetView(snapshot: entry.snapshot)
        }
    }
}

private func toggleAccessibilityLabel(for item: WidgetItemSnapshot) -> Text {
    item.isPurchased
        ? Text("widget.toggle_unmark_a11y \(item.name)")
        : Text("widget.toggle_mark_a11y \(item.name)")
}

/// Accented and vibrant rendering keep only the alpha of every color, so an opaque
/// fill behind a label would swallow it. Outside full color the fill becomes a wash.
private struct WidgetBadgeFill: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let color: Color
    let shape: AnyShape

    func body(content: Content) -> some View {
        content
            .background(color.opacity(renderingMode == .fullColor ? 1 : 0.2), in: shape)
            .widgetAccentable()
    }
}

private extension View {
    func widgetBadge(_ color: Color, in shape: some Shape) -> some View {
        modifier(WidgetBadgeFill(color: color, shape: AnyShape(shape)))
    }
}

// MARK: - Lock Screen Widgets

struct InlineLockScreenWidgetView: View {
    let snapshot: WidgetCartSnapshot

    var body: some View {
        if snapshot.isEmpty {
            Text("widget.inline_empty")
        } else if snapshot.isAllPurchased {
            Text("widget.inline_all_purchased")
        } else {
            let firstItem = snapshot.items.first(where: { !$0.isPurchased })?.name ?? ""
            Text("widget.inline_remaining \(snapshot.remainingCount) \(firstItem)")
        }
    }
}

struct CircularLockScreenWidgetView: View {
    let snapshot: WidgetCartSnapshot

    var body: some View {
        Gauge(
            value: Double(snapshot.purchasedCount),
            in: 0 ... Double(max(1, snapshot.totalCount))
        ) {
            Image(systemName: "cart.fill")
        } currentValueLabel: {
            Text("\(snapshot.remainingCount)")
                .font(.system(.callout, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

struct RectangularLockScreenWidgetView: View {
    let snapshot: WidgetCartSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "cart.fill")
                    .font(.caption2)
                Text(snapshot.cartTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("widget.remaining \(snapshot.remainingCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
            }

            let displayItems = Array(snapshot.items.prefix(2))
            if displayItems.isEmpty {
                Text(snapshot.isEmpty ? "widget.empty" : "widget.all_purchased")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayItems) { item in
                    HStack(spacing: 6) {
                        Button(intent: ToggleProductPurchasedIntent(
                            productID: item.id.uuidString,
                            accountID: snapshot.accountID?.uuidString ?? "",
                            familyID: snapshot.familyID?.uuidString ?? "",
                            isPurchased: !item.isPurchased
                        )) {
                            Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                .font(.footnote)
                                .widgetAccentable(item.isPurchased)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(toggleAccessibilityLabel(for: item))
                        .disabled(snapshot.accountID == nil || snapshot.familyID == nil)

                        Text(item.name)
                            .font(.caption)
                            .strikethrough(item.isPurchased)
                            .foregroundStyle(item.isPurchased ? .secondary : .primary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Home Screen Widgets

struct SmallHomeWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetCartSnapshot

    private var accent: AppAccentColor {
        snapshot.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Icon + Title + Status Pill
            HStack(spacing: 5) {
                Image(systemName: "cart.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OneCartPalette.primary(for: scheme, accent: accent))
                    .widgetAccentable()

                Text(snapshot.cartTitle)
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)

                Spacer(minLength: 2)

                if snapshot.remainingCount > 0 {
                    Text("\(snapshot.remainingCount)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .widgetBadge(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
                } else if !snapshot.isEmpty {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                        .padding(3)
                        .widgetBadge(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Circle())
                }
            }

            Spacer(minLength: 0)

            // Content: Interactive Items or States
            if snapshot.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Image(systemName: "cart")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("widget.empty")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else if snapshot.isAllPurchased {
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(OneCartPalette.primary(for: scheme, accent: accent))
                        .widgetAccentable()
                    Text("widget.all_purchased")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("widget.in_trolley \(snapshot.totalCount) \(snapshot.totalCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                let displayItems = Array(snapshot.items.prefix(2))
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(displayItems) { item in
                        HStack(spacing: 6) {
                            Button(intent: ToggleProductPurchasedIntent(
                                productID: item.id.uuidString,
                                accountID: snapshot.accountID?.uuidString ?? "",
                                familyID: snapshot.familyID?.uuidString ?? "",
                                isPurchased: !item.isPurchased
                            )) {
                                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(
                                        item.isPurchased ? OneCartPalette.primary(for: scheme, accent: accent) : Color
                                            .secondary
                                            .opacity(0.4)
                                    )
                                    .widgetAccentable(item.isPurchased)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(toggleAccessibilityLabel(for: item))
                            .disabled(snapshot.accountID == nil || snapshot.familyID == nil)

                            Text(item.name)
                                .font(.caption2.weight(.medium))
                                .strikethrough(item.isPurchased)
                                .foregroundStyle(item.isPurchased ? .secondary : .primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if item.id != displayItems.last?.id {
                            Divider()
                                .opacity(0.4)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Footer: Custom Sleek Progress Bar + Caption
            if !snapshot.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                            Capsule()
                                .fill(OneCartPalette.primary(for: scheme, accent: accent))
                                .frame(width: max(0, geo.size.width * CGFloat(snapshot.progress)))
                                .widgetAccentable()
                        }
                    }
                    .frame(height: 3.5)

                    HStack {
                        Text("widget.in_trolley \(snapshot.purchasedCount) \(snapshot.totalCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 2)

                        if let partner = snapshot.activePartnerName, !partner.isEmpty {
                            Text(partner)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(14)
    }
}

struct MediumHomeWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetCartSnapshot

    private var accent: AppAccentColor {
        snapshot.accentColor
    }

    var body: some View {
        HStack(spacing: 14) {
            // Left column: Cart Context
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .widgetBadge(
                            OneCartPalette.primary(for: scheme, accent: accent),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }

                Text(snapshot.cartTitle)
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if snapshot.isEmpty {
                    Text("widget.empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("widget.in_trolley \(snapshot.purchasedCount) \(snapshot.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        ProgressView(value: snapshot.progress)
                            .tint(OneCartPalette.primary(for: scheme, accent: accent))
                            .widgetAccentable()

                        Text("\(Int(snapshot.progress * 100))%")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let partner = snapshot.activePartnerName, !partner.isEmpty {
                        Text(partner)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .widgetBadge(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 130, alignment: .leading)

            Divider()

            // Right column: Interactive Items
            VStack(alignment: .leading, spacing: 6) {
                let itemsToShow = Array(snapshot.items.prefix(4))
                if itemsToShow.isEmpty {
                    VStack(alignment: .center, spacing: 6) {
                        Spacer()
                        Image(systemName: "cart.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        // The left column already says the cart is empty.
                        if !snapshot.isEmpty {
                            Text("widget.all_done")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(itemsToShow) { item in
                        HStack(spacing: 8) {
                            Button(intent: ToggleProductPurchasedIntent(
                                productID: item.id.uuidString,
                                accountID: snapshot.accountID?.uuidString ?? "",
                                familyID: snapshot.familyID?.uuidString ?? "",
                                isPurchased: !item.isPurchased
                            )) {
                                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(
                                        item.isPurchased ? OneCartPalette.primary(for: scheme, accent: accent) : Color
                                            .secondary
                                            .opacity(0.4)
                                    )
                                    .widgetAccentable(item.isPurchased)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(toggleAccessibilityLabel(for: item))
                            .disabled(snapshot.accountID == nil || snapshot.familyID == nil)

                            Text(item.name)
                                .font(.footnote.weight(.medium))
                                .strikethrough(item.isPurchased)
                                .foregroundStyle(item.isPurchased ? .secondary : .primary)
                                .lineLimit(1)

                            Spacer(minLength: 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if item.id != itemsToShow.last?.id {
                            Divider()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

struct LargeHomeWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetCartSnapshot

    private var accent: AppAccentColor {
        snapshot.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .widgetBadge(
                            OneCartPalette.primary(for: scheme, accent: accent),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.cartTitle)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        let pct = Int(snapshot.progress * 100)
                        Text("widget.in_trolley_percent \(snapshot.purchasedCount) \(snapshot.totalCount) \(pct)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let partner = snapshot.activePartnerName, !partner.isEmpty {
                    Text(partner)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .widgetBadge(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
                }
            }

            ProgressView(value: snapshot.progress)
                .tint(OneCartPalette.primary(for: scheme, accent: accent))
                .widgetAccentable()

            Divider()

            let displayItems = Array(snapshot.items.prefix(7))
            if displayItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "cart.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("widget.empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(displayItems) { item in
                    HStack(spacing: 10) {
                        Button(intent: ToggleProductPurchasedIntent(
                            productID: item.id.uuidString,
                            accountID: snapshot.accountID?.uuidString ?? "",
                            familyID: snapshot.familyID?.uuidString ?? "",
                            isPurchased: !item.isPurchased
                        )) {
                            Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    item.isPurchased ? OneCartPalette.primary(for: scheme, accent: accent) : Color
                                        .secondary
                                        .opacity(0.4)
                                )
                                .widgetAccentable(item.isPurchased)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(toggleAccessibilityLabel(for: item))
                        .disabled(snapshot.accountID == nil || snapshot.familyID == nil)

                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(item.isPurchased)
                            .foregroundStyle(item.isPurchased ? .secondary : .primary)
                            .lineLimit(1)

                        Spacer()

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if item.id != displayItems.last?.id {
                        Divider()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
