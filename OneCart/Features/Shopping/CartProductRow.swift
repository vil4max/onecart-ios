import SwiftUI

enum CartNameFocus: Hashable {
    case compose
    case edit
}

struct ProductPurchaseToggle: View {
    let isPurchased: Bool
    let canEdit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPurchased ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPurchased ? OneCartPalette.primary : Color.secondary.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!canEdit)
        .accessibilityLabel(
            isPurchased
                ? String(localized: "cart.unmark_trolley_a11y")
                : String(localized: "cart.mark_in_trolley_a11y")
        )
        .accessibilityAddTraits(isPurchased ? [.isSelected] : [])
    }
}

struct CartCategoryThumbnail: View {
    let category: ProductCategory
    let isDimmed: Bool

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(OneCartPalette.primaryAccent)
            .frame(width: 40, height: 40)
            .background(
                OneCartPalette.primarySoft,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(isDimmed ? 0.45 : 1)
            .accessibilityHidden(true)
    }
}

struct ProductRow: View {
    let product: ProductEntity
    let canEdit: Bool
    let isEditing: Bool
    @Binding var editName: String
    var editFocused: FocusState<CartNameFocus?>.Binding
    let isSavingEdit: Bool
    var showsCategoryLabel: Bool = true
    let onToggle: () -> Void
    let onBeginEdit: () -> Void
    let onSubmitEdit: () -> Void

    private var resolvedCategory: ProductCategory {
        let name = isEditing ? editName : product.displayName
        let inferred = ProductCategory.inferred(from: name)
        if inferred != .other {
            return inferred
        }
        return product.categoryValue
    }

    var body: some View {
        HStack(spacing: 12) {
            CartCategoryThumbnail(
                category: resolvedCategory,
                isDimmed: product.isPurchasedValue
            )

            if isEditing {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("cart.add_placeholder", text: $editName)
                        .font(.body)
                        .focused(editFocused, equals: .edit)
                        .submitLabel(.done)
                        .onSubmit(onSubmitEdit)
                        .disabled(isSavingEdit)

                    Text(resolvedCategory.localizedName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button(action: onBeginEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.displayName)
                            .font(.body)
                            .strikethrough(product.isPurchasedValue)
                            .foregroundStyle(product.isPurchasedValue ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if showsCategoryLabel {
                            Text(resolvedCategory.localizedName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if !productSubtitle.isEmpty {
                            Text(productSubtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
            }

            ProductPurchaseToggle(
                isPurchased: product.isPurchasedValue,
                canEdit: canEdit && !isEditing,
                action: onToggle
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var productSubtitle: String {
        if product.isPurchasedValue {
            if let purchasedByName = product.purchasedByName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !purchasedByName.isEmpty
            {
                return String(localized: "cart.in_trolley_by \(purchasedByName)")
            }
            return String(localized: "cart.in_trolley")
        }
        if let createdByName = product.createdByName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !createdByName.isEmpty
        {
            return String(localized: "cart.added_by \(createdByName)")
        }
        return ""
    }
}
