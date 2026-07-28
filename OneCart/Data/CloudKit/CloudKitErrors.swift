import CloudKit
import CoreData
import Foundation

enum OneCartCloudKitError: LocalizedError {
    case accountUnavailable(CKAccountStatus)
    case familyNotShared
    case shareURLUnavailable
    case participantNotFound
    case stillSyncing
    case shareTimedOut

    var errorDescription: String? {
        switch self {
        case let .accountUnavailable(status):
            switch status {
            case .noAccount:
                String(localized: "sync.icloud_no_account")
            case .restricted:
                String(localized: "sync.icloud_restricted")
            case .temporarilyUnavailable:
                String(localized: "sync.icloud_temp_unavailable")
            default:
                String(localized: "sync.icloud_check_failed")
            }
        case .familyNotShared:
            String(localized: "sync.family_not_shared")
        case .shareURLUnavailable:
            String(localized: "sync.share_url_unavailable")
        case .participantNotFound:
            String(localized: "sync.participant_not_found")
        case .stillSyncing:
            String(localized: "sync.still_syncing")
        case .shareTimedOut:
            String(localized: "sync.share_timed_out")
        }
    }
}

enum CloudKitProductReloadPolicy {
    static func shouldReloadProductsAfterEvent(
        type: NSPersistentCloudKitContainer.EventType,
        ended: Bool,
        error: Error?
    ) -> Bool {
        ended && error == nil && type == .import
    }
}

enum CloudKitUserFacingError {
    static var genericSyncFailure: String {
        String(localized: "sync.generic_failure")
    }

    /// TestFlight / App Store use CloudKit Production — new Core Data types must be
    /// deployed from Development in CloudKit Console before they can sync.
    /// This cannot be fixed in the binary alone; the container owner must Deploy Schema.
    static var productionSchemaMissing: String {
        String(localized: "sync.production_schema_missing")
    }

    static func isProductionSchemaFailure(_ error: Error) -> Bool {
        for candidate in flattened(error) {
            if productionSchemaMessage(in: candidate) != nil {
                return true
            }
        }
        return productionSchemaMessage(in: error) != nil
    }

    static func message(for error: Error) -> String {
        // Prefer known CloudKit/Core Data reasons over opaque NSError dumps
        // (mirroring delegate aborts often surface as LocalizedError with English CK text).
        for candidate in flattened(error) {
            if let schema = productionSchemaMessage(in: candidate) {
                return schema
            }
            if let message = message(forCKError: candidate) {
                return message
            }
            if let message = message(forCocoaError: candidate) {
                return message
            }
        }

        if let schema = productionSchemaMessage(in: error) {
            return schema
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription?.nilIfBlank,
           !(error is CKError),
           !looksLikeOpaqueCloudKitCode(description)
        {
            return description
        }

        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || looksLikeOpaqueCloudKitCode(raw) {
            return genericSyncFailure
        }
        if raw.lowercased().contains("not authenticated") || raw.lowercased().contains("not signed in") {
            return String(localized: "sync.sign_in_apple_account")
        }
        return raw
    }

    private static func productionSchemaMessage(in error: Error) -> String? {
        let text = diagnosticText(for: error)
        if text.contains("production schema")
            || text.contains("cannot create new type cd_")
            || (text.contains("cannot create new type") && text.contains("schema"))
            || (text.contains("cd_shoppinglist") && text.contains("schema"))
        {
            return productionSchemaMissing
        }
        return nil
    }

    /// Collects localized + userInfo string crumbs — CK nesting often hides the real reason.
    private static func diagnosticText(for error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = [
            nsError.localizedDescription,
            nsError.localizedFailureReason ?? "",
            nsError.localizedRecoverySuggestion ?? "",
        ]
        for value in nsError.userInfo.values {
            if let string = value as? String {
                parts.append(string)
            } else if let nested = value as? Error {
                parts.append(nested.localizedDescription)
            }
        }
        return parts.joined(separator: "\n").lowercased()
    }

    static func isNetworkError(_ error: Error) -> Bool {
        for candidate in flattened(error) {
            let nsError = candidate as NSError
            if nsError.domain == NSURLErrorDomain {
                return true
            }
            if let ckError = candidate as? CKError {
                switch ckError.code {
                case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy,
                     .requestRateLimited, .serverResponseLost:
                    return true
                default:
                    break
                }
            }
            let text = candidate.localizedDescription.lowercased()
            if text.contains("network connection")
                || text.contains("internet connection")
                || text.contains("timed out")
                || text.contains("could not connect")
                || text.contains("offline")
            {
                return true
            }
        }
        return false
    }

    private static func message(forCKError error: Error) -> String? {
        guard let ckError = error as? CKError else { return nil }
        switch ckError.code {
        case .notAuthenticated:
            return String(localized: "sync.sign_in_apple_account")
        case .networkUnavailable, .networkFailure:
            return String(localized: "sync.network_deferred")
        case .quotaExceeded:
            return String(localized: "sync.quota_exceeded")
        case .accountTemporarilyUnavailable:
            return String(localized: "sync.temporarily_unavailable")
        case .permissionFailure:
            return String(localized: "sync.share_access_denied")
        case .serverRejectedRequest, .invalidArguments, .incompatibleVersion:
            // Schema / argument detail may still be in userInfo — checked earlier via
            // productionSchemaMessage. Fall back only when no specific mapping matched.
            return genericSyncFailure
        case .zoneNotFound, .userDeletedZone:
            return String(localized: "sync.zone_unavailable")
        case .limitExceeded, .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return String(localized: "sync.icloud_overloaded")
        case .partialFailure:
            // Nested item errors carry the real reason; outer code 2 is opaque.
            return nil
        default:
            return nil
        }
    }

    private static func message(forCocoaError error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else { return nil }
        // 133021 = NSManagedObjectConstraintMergeError (unique constraint vs CloudKit import).
        if nsError.code == NSManagedObjectConstraintMergeError {
            return genericSyncFailure
        }
        if nsError.code == NSCloudSharingQuotaExceededError {
            return String(localized: "sync.quota_exceeded")
        }
        return nil
    }

    private static func flattened(_ error: Error) -> [Error] {
        var result: [Error] = []
        var queue: [Error] = [error]
        var depth = 0

        while let current = queue.first, depth < 24 {
            queue.removeFirst()
            depth += 1
            result.append(current)

            let nsError = current as NSError
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying)
            }
            if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [Error] {
                queue.append(contentsOf: detailed)
            }
            if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                queue.append(contentsOf: partial.values)
            } else if let ckError = current as? CKError, let partial = ckError.partialErrorsByItemID {
                queue.append(contentsOf: partial.values)
            }
        }
        return result
    }

    private static func looksLikeOpaqueCloudKitCode(_ raw: String) -> Bool {
        let normalized = raw.lowercased()
        return normalized.contains("ckerrordomain")
            || normalized.contains("ckerror")
            || normalized.contains("mirroring delegate")
            || normalized.contains("partial failure")
            || normalized.contains("failed to modify some records")
            || (normalized.contains("couldn't be completed") && normalized.contains("error"))
            || (normalized.contains("could not be completed") && normalized.contains("error"))
    }
}


private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
