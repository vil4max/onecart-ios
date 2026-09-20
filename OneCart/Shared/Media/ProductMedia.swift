import SwiftUI

struct OfficialProductThumbnail: View {
    let category: ProductCategory
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(OneCartPalette.primarySoft)
            Image(systemName: category.symbolName)
                .font(.system(size: size * 0.37, weight: .semibold))
                .foregroundStyle(OneCartPalette.primaryAccent)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}
