import UIKit

enum CartHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

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

    static func success(_ message: String) -> UserAlert {
        UserAlert(kind: .success, message: message)
    }

    static func error(_ message: String) -> UserAlert {
        UserAlert(kind: .error, message: message)
    }
}
