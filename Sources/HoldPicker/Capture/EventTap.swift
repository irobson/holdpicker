import CoreGraphics
import Foundation

/// Thin wrapper around a `CGEvent` tap.
///
/// The tap is inserted at the session level, ahead of other taps, as an
/// *active* filter: the handler can pass, modify or swallow each event.
/// Events are delivered on the main run loop, so the handler runs on the
/// main actor.
@MainActor
final class EventTap {
    typealias Handler = @MainActor (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    enum Error: Swift.Error, LocalizedError {
        case creationFailed

        var errorDescription: String? {
            "Could not create the event tap. Accessibility permission is probably missing."
        }
    }

    private let mask: CGEventMask
    private let handler: Handler
    /// Called after macOS disabled the tap and it was re-enabled. Events were
    /// lost in between, so any gesture in progress must be abandoned.
    var onReenabled: (@MainActor () -> Void)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(events: [CGEventType], handler: @escaping Handler) {
        self.mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        self.handler = handler
    }

    var isRunning: Bool { port != nil }

    func start() throws {
        guard port == nil else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            throw Error.creationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.port = port
        self.source = source
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
    }

    fileprivate func dispatch(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that take too long. Re-enable and move on.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            onReenabled?()
            return Unmanaged.passUnretained(event)
        default:
            return handler(type, event)
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    // The run loop source lives on the main run loop, so this is the main thread.
    return MainActor.assumeIsolated {
        tap.dispatch(type: type, event: event)
    }
}
