import SwiftUI

extension WidgetCartSnapshot {
    var preferredColorScheme: ColorScheme? {
        switch forcedAppearance {
        case .dark:
            .dark
        case .light:
            .light
        case nil:
            nil
        }
    }
}
