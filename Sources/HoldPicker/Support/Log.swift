import os

/// Unified logging. Read with:
///   log stream --predicate 'subsystem == "dev.holdpicker.HoldPicker"' --level debug
enum Log {
    static let subsystem = "dev.holdpicker.HoldPicker"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let events = Logger(subsystem: subsystem, category: "events")
    static let recording = Logger(subsystem: subsystem, category: "recording")
}
