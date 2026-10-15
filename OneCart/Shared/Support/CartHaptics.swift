import UIKit

/// Haptic feedback a ViewModel or controller plays through its initializer instead of the
/// `CartHaptics` statics, so tests can record it.
@MainActor
protocol HapticsPlaying {
    func light()
    func success()
    func error()
}

struct SystemHaptics: HapticsPlaying {
    func light() {
        CartHaptics.light()
    }

    func success() {
        CartHaptics.success()
    }

    func error() {
        CartHaptics.error()
    }
}

enum CartHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
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

    static func error(_ message: String) -> UserAlert {
        UserAlert(kind: .error, message: message)
    }
}
