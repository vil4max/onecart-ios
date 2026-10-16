import Foundation

/// Who made a cart change: the display name shown on the line and, when the session knows it,
/// the CloudKit user record name that tells two members with the same name apart
/// (REQ-WIDGET-030).
struct CartAuthor: Equatable, Sendable {
    let displayName: String?
    let recordName: String?

    init(displayName: String?, recordName: String? = nil) {
        self.displayName = displayName
        self.recordName = recordName
    }
}
