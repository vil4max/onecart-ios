import UIKit

/// The share thumbnail and invite-sheet icon: the app mark on a rounded tile in the accent's
/// light primary colour. Drawn on demand, only when a share has no thumbnail yet or the share
/// sheet opens.
struct ShareThumbnailRenderer: ShareThumbnailRendering {
    private let accentProvider: @Sendable () -> AppAccentColor

    var accent: AppAccentColor { accentProvider() }

    init(accent: AppAccentColor) {
        accentProvider = { accent }
    }

    /// Reads the accent each time it draws, so a theme picked after launch reaches the first
    /// share's thumbnail (a share keeps the thumbnail it was stamped with).
    init(currentAccent: @escaping @Sendable () -> AppAccentColor) {
        accentProvider = currentAccent
    }

    private static let side: CGFloat = 512

    func thumbnailPNGData() -> Data? {
        image().pngData()
    }

    func image() -> UIImage {
        let size = CGSize(width: Self.side, height: Self.side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rgb = accent.rgb(for: .primary, dark: false)
            UIColor(red: rgb.red / 255, green: rgb.green / 255, blue: rgb.blue / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 112).fill()
            drawMark(in: size)
        }
    }

    private func drawMark(in size: CGSize) {
        if let mark = UIImage(named: "LaunchIcon") {
            mark.draw(in: CGRect(x: 80, y: 80, width: 352, height: 352))
            return
        }
        let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
        guard
            let symbol = UIImage(systemName: "cart.fill", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
        else { return }
        let origin = CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2)
        symbol.draw(at: origin)
    }
}
