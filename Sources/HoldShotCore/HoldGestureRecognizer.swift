import CoreGraphics
import Foundation

/// A pointer event as seen by the recognizer.
///
/// Points are in whatever coordinate space the caller uses. The recognizer only
/// measures distances and builds rectangles from them, so any consistent space works.
public enum PointerInput: Equatable {
    /// Primary button pressed. `modifiers` are the raw `CGEventFlags` at that moment.
    case down(CGPoint, modifiers: UInt64)
    /// Pointer moved while the primary button is held.
    case drag(CGPoint)
    /// Primary button released.
    case up(CGPoint)
    /// The hold timer, armed by `.armTimer`, fired.
    case holdTimeout
    /// The user asked to abort (Escape key).
    case cancel
}

/// What the caller must do with the event that produced a response.
public enum Verdict: Equatable {
    /// Deliver the event to the system untouched.
    case pass
    /// Drop the event.
    case swallow
    /// Drop the event, but keep a copy: it may be replayed later.
    case hold
    /// Re-inject the held event, then re-inject this one, in that order.
    /// The original event must be dropped so ordering is guaranteed.
    case release
}

/// Side effects the caller must perform, in order.
public enum Effect: Equatable {
    case armTimer(TimeInterval)
    case disarmTimer
    case beginSelection(origin: CGPoint)
    case updateSelection(CGRect)
    case commitSelection(CGRect)
    case cancelSelection
}

public struct Response: Equatable {
    public var verdict: Verdict
    public var effects: [Effect]

    public init(_ verdict: Verdict, _ effects: [Effect] = []) {
        self.verdict = verdict
        self.effects = effects
    }
}

public struct HoldGestureConfiguration: Equatable {
    /// How long the button must stay pressed, without moving, to enter selection mode.
    public var holdDuration: TimeInterval
    /// Movement (in points) tolerated during the hold before it counts as a normal drag.
    public var moveTolerance: CGFloat
    /// Modifier flags (raw `CGEventFlags`) that must all be held for the gesture to arm.
    /// `0` means a plain press is enough.
    public var requiredModifiers: UInt64

    public init(holdDuration: TimeInterval = 0.35, moveTolerance: CGFloat = 4, requiredModifiers: UInt64 = 0) {
        self.holdDuration = holdDuration
        self.moveTolerance = moveTolerance
        self.requiredModifiers = requiredModifiers
    }
}

/// Recognizes the "press and hold, then drag" gesture without breaking ordinary clicks.
///
/// The trick is *hold-and-replay*: the mouse-down is intercepted and kept aside.
/// If the user releases or moves before the hold timer fires, the original
/// mouse-down is re-injected followed by the current event, and the system
/// never notices. If the timer fires first, the app owns the pointer until
/// the button is released, and the resulting rectangle is reported.
///
/// This type is pure: it performs no I/O and owns no timer. The caller applies
/// the returned `Verdict` and `Effect`s. That keeps it trivially testable.
public final class HoldGestureRecognizer {
    public enum State: Equatable {
        case idle
        /// Button is down, timer armed, waiting to see whether this is a hold.
        case pending(origin: CGPoint)
        /// A normal click or drag is in progress; events flow untouched until mouse-up.
        case passthrough
        /// The overlay is up and the user is dragging out a rectangle.
        case selecting(origin: CGPoint)
    }

    public private(set) var state: State = .idle
    public var configuration: HoldGestureConfiguration

    public init(configuration: HoldGestureConfiguration = .init()) {
        self.configuration = configuration
    }

    public var isSelecting: Bool {
        if case .selecting = state { return true }
        return false
    }

    public func handle(_ input: PointerInput) -> Response {
        switch (state, input) {

        // MARK: idle
        case let (.idle, .down(point, modifiers)):
            guard modifiers & configuration.requiredModifiers == configuration.requiredModifiers else {
                return Response(.pass)
            }
            state = .pending(origin: point)
            return Response(.hold, [.armTimer(configuration.holdDuration)])

        case (.idle, _):
            return Response(.pass)

        // MARK: pending
        case let (.pending(origin), .drag(point)):
            if origin.distance(to: point) > configuration.moveTolerance {
                state = .passthrough
                return Response(.release, [.disarmTimer])
            }
            return Response(.swallow)

        case (.pending, .up):
            state = .idle
            return Response(.release, [.disarmTimer])

        case let (.pending(origin), .holdTimeout):
            state = .selecting(origin: origin)
            return Response(.swallow, [.beginSelection(origin: origin)])

        case (.pending, .down), (.pending, .cancel):
            // A second press without a release cannot happen; a cancel while
            // pending has nothing to cancel yet. Ignore both.
            return Response(.swallow)

        // MARK: passthrough
        case (.passthrough, .up):
            state = .idle
            return Response(.pass)

        case (.passthrough, _):
            return Response(.pass)

        // MARK: selecting
        case let (.selecting(origin), .drag(point)):
            return Response(.swallow, [.updateSelection(CGRect(corner: origin, opposite: point))])

        case let (.selecting(origin), .up(point)):
            state = .idle
            return Response(.swallow, [.commitSelection(CGRect(corner: origin, opposite: point))])

        case (.selecting, .cancel):
            state = .idle
            return Response(.swallow, [.cancelSelection])

        case (.selecting, _):
            return Response(.swallow)
        }
    }

    /// Forces the recognizer back to `.idle`. Use when the event tap restarts.
    public func reset() {
        state = .idle
    }
}
