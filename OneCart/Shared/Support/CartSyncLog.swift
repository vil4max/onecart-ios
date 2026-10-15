import OSLog

enum CartSyncLog {
    static let cart = Logger(subsystem: OneCartLog.subsystem, category: "CartSync")
    static let shareACL = Logger(subsystem: OneCartLog.subsystem, category: "ShareACL")
    static let action = Logger(subsystem: OneCartLog.subsystem, category: "Action")
}
