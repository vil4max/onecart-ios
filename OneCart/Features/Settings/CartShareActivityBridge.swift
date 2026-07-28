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
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
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

