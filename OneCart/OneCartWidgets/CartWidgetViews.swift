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
        // supportedFamilies does not offer this iOS 27 family, but leaving a known case to
        // @unknown default warns at build time, so map it like the other large layouts.
        case .systemExtraLargePortrait:
            LargeHomeWidgetView(snapshot: entry.snapshot)
        @unknown default:
            MediumHomeWidgetView(snapshot: entry.snapshot)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cart.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                    .widgetAccentable()
                    .accessibilityHidden(true)

                Text(snapshot.cartTitle)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 2)

                if snapshot.remainingCount > 0 {
                    Text(snapshot.remainingCount, format: .number)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .widgetBadge(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
                }
            }

            if snapshot.isEmpty {
                WidgetEmptyState()
            } else {
                Spacer(minLength: 0)

                let displayItems = Array(snapshot.items.prefix(2))
                if displayItems.isEmpty {
                    Text("widget.all_done")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(displayItems) { item in
                            WidgetItemRow(
                                item: item,
                                snapshot: snapshot,
                                accent: accent,
                                thumbnailSize: 22,
                                nameFont: .footnote,
                                toggleFont: .title3
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                WidgetProgressLine(
                    snapshot: snapshot,
                    accent: accent,
                    isCompact: true,
                    partnerName: snapshot.activePartnerName
                )
            }
        }
        .padding(14)
    }
}

struct MediumHomeWidgetView: View {
    let snapshot: WidgetCartSnapshot

    private var accent: AppAccentColor {
        snapshot.accentColor
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetCartTile(accent: accent, size: 34)

                Text(snapshot.cartTitle)
                    .font(.headline)
                    .lineLimit(1)

                if snapshot.isEmpty {
                    Text("widget.empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    WidgetProgressLine(snapshot: snapshot, accent: accent)

                    if let partner = snapshot.activePartnerName, !partner.isEmpty {
                        WidgetPartnerChip(name: partner, accent: accent)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 130, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                let itemsToShow = Array(snapshot.items.prefix(4))
                if itemsToShow.isEmpty {
                    if snapshot.isEmpty {
                        // The left column already says the cart is empty.
                        WidgetEmptyState(symbolFont: .title2, showsCaption: false)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("widget.all_done")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ForEach(itemsToShow) { item in
                        WidgetItemRow(
                            item: item,
                            snapshot: snapshot,
                            accent: accent,
                            thumbnailSize: 24,
                            nameFont: .footnote,
                            toggleFont: .title3
                        )

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
    let snapshot: WidgetCartSnapshot

    private var accent: AppAccentColor {
        snapshot.accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                WidgetCartTile(accent: accent, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.cartTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if snapshot.isEmpty {
                        Text("widget.empty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        WidgetProgressLine(snapshot: snapshot, accent: accent)
                    }
                }

                if let partner = snapshot.activePartnerName, !partner.isEmpty {
                    Spacer(minLength: 4)
                    WidgetPartnerChip(name: partner, accent: accent)
                }
            }

            Divider()

            let displayItems = Array(snapshot.items.prefix(7))
            if displayItems.isEmpty {
                WidgetEmptyState(symbolFont: .largeTitle)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displayItems) { item in
                        WidgetItemRow(
                            item: item,
                            snapshot: snapshot,
                            accent: accent,
                            thumbnailSize: 26,
                            nameFont: .subheadline,
                            toggleFont: .title2,
                            showsSubtitle: true
                        )

                        if item.id != displayItems.last?.id {
                            Divider()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Previews

#if DEBUG
    extension WidgetCartSnapshot {
        /// Placeholder content with account and cart identity so the toggles render enabled.
        static let previewSample = WidgetCartSnapshot(
            cartTitle: placeholder.cartTitle,
            totalCount: placeholder.totalCount,
            purchasedCount: placeholder.purchasedCount,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 2,
            activePartnerName: "Alex",
            accountID: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1"),
            familyID: UUID(uuidString: "00000000-0000-0000-0000-0000000000F1"),
            items: placeholder.items
        )

        static let previewAllPurchased = WidgetCartSnapshot(
            cartTitle: placeholder.cartTitle,
            totalCount: 2,
            purchasedCount: 2,
            isSyncing: false,
            lastUpdated: Date(),
            familyMemberCount: 1,
            accountID: previewSample.accountID,
            familyID: previewSample.familyID,
            items: placeholder.items.prefix(2).map {
                WidgetItemSnapshot(id: $0.id, name: $0.name, isPurchased: true, categoryRaw: $0.categoryRaw)
            }
        )
    }

    #Preview("Small", as: .systemSmall) {
        CartOverviewWidget()
    } timeline: {
        CartWidgetEntry(date: .now, snapshot: .previewSample)
        CartWidgetEntry(date: .now, snapshot: .previewAllPurchased)
        CartWidgetEntry(date: .now, snapshot: .empty)
    }

    #Preview("Medium", as: .systemMedium) {
        CartOverviewWidget()
    } timeline: {
        CartWidgetEntry(date: .now, snapshot: .previewSample)
        CartWidgetEntry(date: .now, snapshot: .previewAllPurchased)
        CartWidgetEntry(date: .now, snapshot: .empty)
    }

    #Preview("Large", as: .systemLarge) {
        CartOverviewWidget()
    } timeline: {
        CartWidgetEntry(date: .now, snapshot: .previewSample)
        CartWidgetEntry(date: .now, snapshot: .empty)
    }
#endif
