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
        @unknown default:
            MediumHomeWidgetView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Lock Screen Widgets

struct InlineLockScreenWidgetView: View {
    let snapshot: WidgetCartSnapshot

    var body: some View {
        if snapshot.isEmpty || snapshot.isAllPurchased {
            Text("🛒 Все куплено")
        } else {
            let firstItem = snapshot.items.first(where: { !$0.isPurchased })?.name ?? ""
            Text("🛒 \(snapshot.remainingCount) ост.: \(firstItem)")
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
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
                Text("\(snapshot.remainingCount) ост.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let displayItems = Array(snapshot.items.prefix(2))
            if displayItems.isEmpty {
                Text("Все куплено!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayItems) { item in
                    HStack(spacing: 6) {
                        Button(intent: ToggleProductPurchasedIntent(productID: item.id.uuidString)) {
                            Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)

                        Text(item.name)
                            .font(.system(size: 12))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OneCartPalette.primary(for: scheme, accent: accent))

                Text(snapshot.cartTitle)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)

                Spacer(minLength: 2)

                if snapshot.remainingCount > 0 {
                    Text("\(snapshot.remainingCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
                } else if !snapshot.isEmpty {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                        .padding(3)
                        .background(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Circle())
                }
            }

            Spacer(minLength: 0)

            // Content: Interactive Items or States
            if snapshot.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Image(systemName: "cart")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("Корзина пуста")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else if snapshot.isAllPurchased {
                VStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(OneCartPalette.primary(for: scheme, accent: accent))
                    Text("Все куплено!")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("\(snapshot.totalCount) из \(snapshot.totalCount) в тележке")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                let displayItems = Array(snapshot.items.prefix(2))
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(displayItems) { item in
                        HStack(spacing: 6) {
                            Button(intent: ToggleProductPurchasedIntent(productID: item.id.uuidString)) {
                                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(
                                        item.isPurchased ? OneCartPalette.primary(for: scheme, accent: accent) : Color
                                            .secondary
                                            .opacity(0.4)
                                    )
                            }
                            .buttonStyle(.plain)

                            Text(item.name)
                                .font(.system(size: 11, weight: .medium))
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
                        }
                    }
                    .frame(height: 3.5)

                    HStack {
                        Text("\(snapshot.purchasedCount) из \(snapshot.totalCount) в тележке")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        if let partner = snapshot.activePartnerName, !partner.isEmpty {
                            Text(partner)
                                .font(.system(size: 9, weight: .medium))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            OneCartPalette.primary(for: scheme, accent: accent),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }

                Text(snapshot.cartTitle)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if snapshot.isEmpty {
                    Text("Корзина пуста")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(snapshot.purchasedCount) из \(snapshot.totalCount) в тележке")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        ProgressView(value: snapshot.progress)
                            .tint(OneCartPalette.primary(for: scheme, accent: accent))

                        Text("\(Int(snapshot.progress * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let partner = snapshot.activePartnerName, !partner.isEmpty {
                        Text(partner)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(OneCartPalette.primaryAccent(for: scheme, accent: accent))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
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
                        Text("Все покупки сделаны!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(itemsToShow) { item in
                        HStack(spacing: 8) {
                            Button(intent: ToggleProductPurchasedIntent(productID: item.id.uuidString)) {
                                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(
                                        item.isPurchased ? OneCartPalette.primary(for: scheme, accent: accent) : Color
                                            .secondary
                                            .opacity(0.4)
                                    )
                            }
                            .buttonStyle(.plain)

                            Text(item.name)
                                .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            OneCartPalette.primary(for: scheme, accent: accent),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.cartTitle)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        let pct = Int(snapshot.progress * 100)
                        Text("\(snapshot.purchasedCount) из \(snapshot.totalCount) в тележке (\(pct)%)")
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
                        .background(OneCartPalette.primarySoft(for: scheme, accent: accent), in: Capsule())
                }
            }

            ProgressView(value: snapshot.progress)
                .tint(OneCartPalette.primary(for: scheme, accent: accent))

            Divider()

            let displayItems = Array(snapshot.items.prefix(7))
            if displayItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "cart.badge.plus")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Корзина пуста")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(displayItems) { item in
                    HStack(spacing: 10) {
                        Button(intent: ToggleProductPurchasedIntent(productID: item.id.uuidString)) {
                            Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    item.isPurchased ? OneCartPalette.primary(for: scheme, accent: accent) : Color
                                        .secondary
                                        .opacity(0.4)
                                )
                        }
                        .buttonStyle(.plain)

                        Text(item.name)
                            .font(.system(size: 14, weight: .medium))
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
