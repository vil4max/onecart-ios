import Foundation

/// The widget snapshot and purchase queue live in `WidgetPurchaseSync`; reloads, preference
/// changes, the scene and the cloud coordinator reach them through the session.
extension AppSession {
    func updateWidgetSnapshot(accentOverride: AppAccentColor? = nil) {
        widgetSync.updateWidgetSnapshot(accentOverride: accentOverride)
    }

    func drainWidgetPendingToggles() async {
        await widgetSync.drainWidgetPendingToggles()
    }
}
