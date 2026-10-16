import Foundation

/// Draws the image CloudKit stores as a share's thumbnail. Data only stamps the bytes: the app
/// target renders them with UIKit in the accent it passes in, so this layer imports neither
/// UIKit nor a process-wide accent.
protocol ShareThumbnailRendering: Sendable {
    /// PNG bytes, or nil when nothing could be drawn; a nil result leaves the share unstamped.
    func thumbnailPNGData() -> Data?
}
