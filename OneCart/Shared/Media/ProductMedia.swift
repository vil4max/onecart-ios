import SwiftUI

struct OfficialProductThumbnail: View {
    let category: ProductCategory
    var isPurchased = false
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OneCartPalette.primary.opacity(0.13),
                    OneCartPalette.primary.opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: category.systemImage)
                .font(.system(size: size * 0.37, weight: .semibold))
                .foregroundColor(OneCartPalette.primary.opacity(0.78))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .saturation(isPurchased ? 0.2 : 1)
        .opacity(isPurchased ? 0.68 : 1)
    }
}

extension ProductCategory {
    var systemImage: String {
        switch self {
        case .produce:
            "leaf.fill"
        case .dairy:
            "drop.fill"
        case .meat:
            "fork.knife"
        case .drinks:
            "waterbottle.fill"
        case .household:
            "sparkles"
        case .other:
            "shippingbox.fill"
        }
    }
}
