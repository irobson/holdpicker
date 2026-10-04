import CoreGraphics
import Foundation

/// What a completed gesture produces.
public enum CaptureMode: Equatable, Sendable {
    /// A still image copied to the clipboard.
    case screenshot
    /// A video of the dragged region with system audio, saved to disk.
    case recording
}

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
    case beginSelection(origin: CGPoint, mode: CaptureMode)
    case updateSelection(CGRect)
    case commitSelection(CGRect, mode: CaptureMode)
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
    /// Raw `CGEventFlags.maskShift`.
    public static let shiftModifier: UInt64 = 1 << 17

    /// How long the button must stay pressed, without moving, to enter selection mode.
    public var holdDuration: TimeInterval
    /// Movement (in points) tolerated during the hold before it counts as a normal drag.
    public var moveTolerance: CGFloat
    /// Modifier flags (raw `CGEventFlags`) that must all be held for the gesture to arm.
    /// `0` means a plain press is enough.
    public var requiredModifiers: UInt64
    /// Extra modifier that switches the gesture from screenshot to recording.
    /// `0` disables recording entirely.
    public var recordingModifier: UInt64
    /// When `false`, a press carrying `recordingModifier` is ignored (passed through).
    /// Used while a recording is already running.
    public var allowsRecording: Bool

    public init(
        holdDuration: TimeInterval = 0.35,
        moveTolerance: CGFloat = 4,
        requiredModifiers: UInt64 = 0,
        recordingModifier: UInt64 = HoldGestureConfiguration.shiftModifier,
        allowsRecording: Bool = true
    ) {
        self.holdDuration = holdDuration
        self.moveTolerance = moveTolerance
        self.requiredModifiers = requiredModifiers
        self.recordingModifier = recordingModifier
        self.allowsRecording = allowsRecording
    }

    /// Decides which mode a press starts, or `nil` if the press is not a gesture candidate.
    func mode(for modifiers: UInt64) -> CaptureMode? {
        guard modifiers & requiredModifiers == requiredModifiers else { return nil }
        let wantsRecording = recordingModifier != 0 && modifiers & recordingModifier == recordingModifier
        guard wantsRecording else { return .screenshot }
        return allowsRecording ? .recording : nil
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
/// The modifiers held at mouse-down pick the mode: plain press for a screenshot,
/// with the recording modifier (Shift by default) for a screen recording.
///
/// This type is pure: it performs no I/O and owns no timer. The caller applies
/// the returned `Verdict` and `Effect`s. That keeps it trivially testable.
public final class HoldGestureRecognizer {
    public enum State: Equatable {
        case idle
        /// Button is down, timer armed, waiting to see whether this is a hold.
        case pending(origin: CGPoint, mode: CaptureMode)
        /// A normal click or drag is in progress; events flow untouched until mouse-up.
        case passthrough
        /// The overlay is up and the user is dragging out a rectangle.
        case selecting(origin: CGPoint, mode: CaptureMode)
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
            guard let mode = configuration.mode(for: modifiers) else {
                return Response(.pass)
            }
            state = .pending(origin: point, mode: mode)
            return Response(.hold, [.armTimer(configuration.holdDuration)])

        case (.idle, _):
            return Response(.pass)

        // MARK: pending
        case let (.pending(origin, _), .drag(point)):
            if origin.distance(to: point) > configuration.moveTolerance {
                state = .passthrough
                return Response(.release, [.disarmTimer])
            }
            return Response(.swallow)

        case (.pending, .up):
            state = .idle
            return Response(.release, [.disarmTimer])

        case let (.pending(origin, mode), .holdTimeout):
            state = .selecting(origin: origin, mode: mode)
            return Response(.swallow, [.beginSelection(origin: origin, mode: mode)])

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
        case let (.selecting(origin, _), .drag(point)):
            return Response(.swallow, [.updateSelection(CGRect(corner: origin, opposite: point))])

        case let (.selecting(origin, mode), .up(point)):
            state = .idle
            return Response(.swallow, [.commitSelection(CGRect(corner: origin, opposite: point), mode: mode)])

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
