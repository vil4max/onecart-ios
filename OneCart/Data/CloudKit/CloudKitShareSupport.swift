import CloudKit
import UIKit

enum OneCartShareBranding {
    static let title = "OneCart"

    /// Applies CloudKit share card branding. Returns `true` when the share was mutated.
    @discardableResult
    static func apply(to share: CKShare) -> Bool {
        var changed = false
        if (share[CKShare.SystemFieldKey.title] as? String) != title {
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue
            changed = true
        }
        if share[CKShare.SystemFieldKey.thumbnailImageData] == nil {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnailImageData as CKRecordValue
            changed = true
        }
        return changed
    }

    static let thumbnailImage: UIImage = {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 52 / 255, green: 120 / 255, blue: 91 / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 112).fill()

            let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
            guard let symbol = UIImage(systemName: "cart.fill", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            else { return }
            let origin = CGPoint(
                x: (size.width - symbol.size.width) / 2,
                y: (size.height - symbol.size.height) / 2
            )
            symbol.draw(at: origin)
        }
    }()

    static let thumbnailImageData: Data = thumbnailImage.pngData() ?? Data()
}

enum OneCartShareLinkJoin {
    /// Ensures link-join and every non-owner participant can edit the cart.
    /// `publicPermission` alone is not enough: invitees who already accepted with
    /// `.readOnly` keep that participant permission until the owner upgrades it.
    @discardableResult
    static func applyReadWriteACL(to share: CKShare) -> Bool {
        var changed = false
        if share.publicPermission != .readWrite {
            share.publicPermission = .readWrite
            changed = true
        }
        for participant in share.participants where participant.role != .owner {
            guard participant.permission != .readWrite else { continue }
            participant.permission = .readWrite
            changed = true
        }
        return changed
    }
}
