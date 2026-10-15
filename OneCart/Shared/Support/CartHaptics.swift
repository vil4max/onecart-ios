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
