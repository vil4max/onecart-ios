import Foundation

enum AppleSignInError: LocalizedError {
    case missingIdentityToken
    case failed

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            String(localized: "auth.apple_missing_credentials")
        case .failed:
            String(localized: "auth.apple_failed")
        }
    }
}
