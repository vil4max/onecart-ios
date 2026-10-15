import Foundation

public enum OneCartAppGroup {
    public static let identifier = "group.com.vil555tim.onecart"
    /// The accent the app last chose; the widget and the palette read it before a snapshot exists.
    public static let accentColorKey = "onecart.accent-color"
    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
