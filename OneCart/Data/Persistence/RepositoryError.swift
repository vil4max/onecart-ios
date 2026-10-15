import Foundation

enum RepositoryError: LocalizedError, Equatable {
    case familySpaceNotFound
    case listNotFound
    case productNotFound
    case storeNotFound
    case permissionDenied
    case crossShareRelationship
    case invalidName

    var errorDescription: String? {
        switch self {
        case .familySpaceNotFound:
            String(localized: "sync.error.family_not_found")
        case .listNotFound:
            String(localized: "sync.error.list_not_found")
        case .productNotFound:
            String(localized: "sync.error.product_not_found")
        case .storeNotFound:
            String(localized: "sync.error.store_not_found")
        case .permissionDenied:
            String(localized: "sync.error.permission_denied")
        case .crossShareRelationship:
            String(localized: "sync.error.cross_share")
        case .invalidName:
            String(localized: "sync.error.invalid_name")
        }
    }
}
