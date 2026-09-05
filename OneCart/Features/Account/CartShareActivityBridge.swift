import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CartSharePayload: Identifiable {
    let id = UUID()
    let link: FamilyInviteLink
}

struct CartActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.permittedArrowDirections = []
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            if let window = activeScene?.windows.first(where: \.isKeyWindow) ?? activeScene?.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            }
        }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

final class CartInviteActivityItem: NSObject, UIActivityItemSource {
    let link: FamilyInviteLink

    init(link: FamilyInviteLink) {
        self.link = link
    }

    func activityViewControllerPlaceholderItem(_: UIActivityViewController) -> Any {
        link.url
    }

    func activityViewController(
        _: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        if activityType == .mail || activityType == .message || activityType == .postToFacebook {
            return link.shareMessage
        }
        return link.url
    }

    func activityViewControllerLinkMetadata(_: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = link.url
        metadata.url = link.url
        metadata.title = link.shareTitle
        let image = OneCartShareBranding.thumbnailImage
        metadata.iconProvider = NSItemProvider(object: image)
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }

    func activityViewController(
        _: UIActivityViewController,
        subjectForActivityType _: UIActivity.ActivityType?
    ) -> String {
        link.shareTitle
    }
}
