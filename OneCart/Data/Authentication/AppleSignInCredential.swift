import Foundation

/// The app requests only the full name. Keychain payloads written by older builds also carry an
/// `email` key; decoding ignores it, and the next save drops it.
struct AppleSignInCredential: Codable, Equatable {
    let userID: String
    let givenName: String?
    let familyName: String?

    var providedDisplayName: String? {
        let parts = [givenName, familyName]
            .compactMap { $0?.nilIfBlank }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    var displayName: String {
        providedDisplayName ?? String(localized: "common.default_user")
    }

    var accountID: UUID {
        OneCartStableID.uuid(for: "apple:\(userID)")
    }
}
