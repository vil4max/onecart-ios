import Foundation

enum UserAlertKind: Equatable {
    case success
    case error

    var title: String {
        switch self {
        case .success:
            String(localized: "alert.title.success")
        case .error:
            String(localized: "alert.title.error")
        }
    }
}

struct UserAlert: Equatable {
    let kind: UserAlertKind
    let message: String

    static func error(_ message: String) -> UserAlert {
        UserAlert(kind: .error, message: message)
    }
}
