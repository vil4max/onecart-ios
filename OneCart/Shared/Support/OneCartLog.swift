import OSLog

/// The unified-log subsystem for the app and the widget extension, so Console filters on
/// one value.
enum OneCartLog {
    static let subsystem = "com.vil555tim.onecart"
}

enum CartSyncLog {
    static let cart = Logger(subsystem: OneCartLog.subsystem, category: "CartSync")
    static let shareACL = Logger(subsystem: OneCartLog.subsystem, category: "ShareACL")
    static let action = Logger(subsystem: OneCartLog.subsystem, category: "Action")
}
