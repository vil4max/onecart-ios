import SwiftUI

struct ProductToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct ProductPurchaseToggle: View {
    let isPurchased: Bool
    let canEdit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPurchased ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPurchased ? OneCartPalette.primary : Color.secondary.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ProductToggleButtonStyle())
        .disabled(!canEdit)
        .accessibilityLabel(
            Text(isPurchased ? "cart.unmark_trolley_a11y" : "cart.mark_in_trolley_a11y")
        )
        .accessibilityAddTraits(isPurchased ? [.isSelected] : [])
    }
}

struct CartCategoryThumbnail: View {
    let category: ProductCategory
    let isDimmed: Bool

    @ScaledMetric(relativeTo: .body) private var size = 36

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(OneCartPalette.primaryAccent)
            .frame(width: size, height: size)
            .background(
                OneCartPalette.primarySoft,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(isDimmed ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.25), value: isDimmed)
            .accessibilityHidden(true)
    }
}

/// One cart line: category tile, name (tap to rename), who added or completed it, and the check control.
struct CartProductRow: View {
    let product: ProductEntity
    let canEdit: Bool
    var showsCategoryLabel = false
    var isHighlighted = false
    let onToggle: () -> Void
    let onRename: () -> Void

    private var isPurchased: Bool {
        product.isPurchasedValue
    }

    private var resolvedCategory: ProductCategory {
        // The stored category drives section grouping, so the icon must agree with it;
        // keyword inference only fills a missing category.
        let stored = product.categoryValue
        if stored != .other {
            return stored
        }
        let inferred = ProductCategory.inferred(from: product.displayName)
        return inferred != .other ? inferred : stored
    }

    var body: some View {
        HStack(spacing: 12) {
            CartCategoryThumbnail(category: resolvedCategory, isDimmed: isPurchased)

            Button(action: onRename) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.body)
                        .strikethrough(isPurchased)
                        .foregroundStyle(isPurchased ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .animation(.easeInOut(duration: 0.25), value: isPurchased)

                    if showsCategoryLabel {
                        Text(resolvedCategory.localizedTitleKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let caption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityHint(canEdit ? Text("cart.rename_hint") : Text(""))

            ProductPurchaseToggle(isPurchased: isPurchased, canEdit: canEdit, action: onToggle)
        }
        .padding(.vertical, 2)
        .background {
            // Always in the hierarchy so the duplicate flash fades in and out instead of popping.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OneCartPalette.primarySoft)
                .padding(.vertical, -6)
                .padding(.horizontal, -8)
                .opacity(isHighlighted ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .accessibilityElement(children: .contain)
    }

    private var caption: LocalizedStringKey? {
        if isPurchased {
            if let purchasedByName = product.purchasedByName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !purchasedByName.isEmpty
            {
                return "cart.in_trolley_by \(purchasedByName)"
            }
            return "cart.in_trolley"
        }
        if let createdByName = product.createdByName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !createdByName.isEmpty
        {
            return "cart.added_by \(createdByName)"
        }
        return nil
    }
}
