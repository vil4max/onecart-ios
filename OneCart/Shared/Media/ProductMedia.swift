import SwiftUI

struct OfficialProductThumbnail: View {
    let category: ProductCategory
    var isPurchased = false
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(OneCartPalette.primarySoft)
            Image(systemName: category.systemImage)
                .font(.system(size: size * 0.37, weight: .semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .saturation(isPurchased ? 0.35 : 1)
        .opacity(isPurchased ? 0.72 : 1)
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
