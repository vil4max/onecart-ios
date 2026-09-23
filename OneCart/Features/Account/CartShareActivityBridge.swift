import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CartSharePayload: Identifiable {
    let id = UUID()
    let link: FamilyInviteLink
}

extension View {
    /// Presents the invite share sheet from the view that opened it. A wide scene (an unfolded
    /// iPhone Duo) shows a popover pointing at that control instead of one pinned to the window
    /// centre, which is the fold; a compact iPhone keeps the full-height sheet it always had.
    func cartSharePresentation(item: Binding<CartSharePayload?>) -> some View {
        popover(item: item, arrowEdge: .top) { payload in
            CartActivityViewController(activityItems: [CartInviteActivityItem(link: payload.link)])
                // The share sheet draws its own background to the bottom edge, as it did when
                // it was presented with `.sheet`.
                .ignoresSafeArea()
                .presentationCompactAdaptation(.sheet)
        }
    }
}

/// Hosted as the content of `cartSharePresentation`, so SwiftUI owns the presentation and its
/// anchor; the controller configures no popover of its own.
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
