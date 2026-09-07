import CloudKit
import UIKit

enum CloudKitShareEnvironment: String {
    case production
    case development
    case unknown

    static var process: CloudKitShareEnvironment {
        .production
    }

    static func fromDiagnostic(_ text: String) -> CloudKitShareEnvironment {
        let normalized = text.lowercased()
        if normalized.contains("environment=production")
            || normalized.contains("environment: production")
            || normalized.contains(", environment=production")
        {
            return .production
        }
        if normalized.contains("environment=sandbox")
            || normalized.contains("environment=development")
            || normalized.contains("environment: sandbox")
            || normalized.contains("environment: development")
        {
            return .development
        }
        return .unknown
    }

    static func diagnostic(for share: CKShare) -> String {
        var parts = [String(describing: share)]
        for key in ["containerID", "containerIdentifier", "_containerID"] {
            if let value = share.value(forKey: key) {
                parts.append("\(key)=\(String(describing: value))")
            }
        }
        return parts.joined(separator: " ")
    }

    static func of(_ share: CKShare) -> CloudKitShareEnvironment {
        fromDiagnostic(diagnostic(for: share))
    }

    static func canMutateInProcess(_ share: CKShare) -> Bool {
        let shareEnvironment = of(share)
        if shareEnvironment == .unknown {
            return true
        }
        return shareEnvironment == process
    }
}

enum OneCartShareBranding {
    static let title = "OneCart Family"

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
            let rgb = OneCartPalette.currentAccent.primaryRGB.light
            UIColor(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 112).fill()

            if let mark = UIImage(named: "LaunchIcon") {
                let inset = CGRect(x: 80, y: 80, width: 352, height: 352)
                mark.draw(in: inset)
            } else {
                let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
                if let symbol = UIImage(systemName: "cart.fill", withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                {
                    let origin = CGPoint(
                        x: (size.width - symbol.size.width) / 2,
                        y: (size.height - symbol.size.height) / 2
                    )
                    symbol.draw(at: origin)
                }
            }
        }
    }()

    static let thumbnailImageData: Data = thumbnailImage.pngData() ?? Data()
}

enum OneCartShareLinkJoin {
    @discardableResult
    static func applyReadWriteACL(to share: CKShare, reopenInviteDoor: Bool = false) -> Bool {
        var changed = false
        let mayTouchPublicPermission = reopenInviteDoor || share.publicPermission != .none
        if mayTouchPublicPermission, share.publicPermission != .readWrite {
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
