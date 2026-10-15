import AuthenticationServices
import UIKit

@MainActor
enum AppleSignInPresentationAnchor {
    static var current: ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let preferredScenes = scenes.filter {
            $0.activationState == .foregroundActive
                || $0.activationState == .foregroundInactive
        }
        let orderedScenes = preferredScenes.isEmpty ? scenes : preferredScenes

        for scene in orderedScenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        for scene in orderedScenes {
            if let window = scene.windows.first(where: { !$0.isHidden }) {
                return window
            }
        }
        if let scene = orderedScenes.first ?? scenes.first {
            return UIWindow(windowScene: scene)
        }
        preconditionFailure("No UIWindowScene for Sign in with Apple presentation")
    }
}
