import os

/// Unified logging. Read with:
///   log stream --predicate 'subsystem == "dev.holdshot.HoldShot"' --level debug
enum Log {
    static let subsystem = "dev.holdshot.HoldShot"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let events = Logger(subsystem: subsystem, category: "events")
}
