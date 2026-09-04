import OSLog

/// One logger per area so `log show --predicate 'subsystem == "com.mehulfursule.nomi"'` finds everything.
nonisolated enum Log {
    static let subsystem = "com.mehulfursule.nomi"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let agent = Logger(subsystem: subsystem, category: "agent")
}
