import CoreGraphics
import Foundation
import HoldShotCore

/// User-facing settings, persisted in `UserDefaults`.
///
/// Every property reads through to defaults on access, so the menu and the
/// capture pipeline always agree without an observer layer. Override from the
/// shell with, for example:
///   defaults write dev.holdshot.HoldShot holdDuration -float 0.5
final class Preferences {
    static let shared = Preferences()

    enum Key {
        static let isEnabled = "isEnabled"
        static let holdDuration = "holdDuration"
        static let moveTolerance = "moveTolerance"
        static let requiredModifiers = "requiredModifiers"
        static let playsSound = "playsSound"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Master switch. When off, the event tap is torn down and clicks are never touched.
    var isEnabled: Bool {
        get { defaults.object(forKey: Key.isEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    /// Seconds the button must stay still before selection mode starts.
    var holdDuration: TimeInterval {
        get { defaults.object(forKey: Key.holdDuration) as? Double ?? 0.35 }
        set { defaults.set(newValue, forKey: Key.holdDuration) }
    }

    /// Points of movement tolerated during the hold.
    var moveTolerance: CGFloat {
        get { defaults.object(forKey: Key.moveTolerance) as? Double ?? 4 }
        set { defaults.set(Double(newValue), forKey: Key.moveTolerance) }
    }

    /// Modifier keys that must be held together with the press. Empty means none.
    var requiredModifiers: CGEventFlags {
        get {
            let raw = defaults.object(forKey: Key.requiredModifiers) as? Int ?? 0
            return CGEventFlags(rawValue: UInt64(raw))
        }
        set { defaults.set(Int(newValue.rawValue), forKey: Key.requiredModifiers) }
    }

    /// Play a short system sound after a capture lands in the clipboard.
    var playsSound: Bool {
        get { defaults.object(forKey: Key.playsSound) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.playsSound) }
    }

    /// Snapshot of the gesture-related settings for the recognizer.
    var gestureConfiguration: HoldGestureConfiguration {
        HoldGestureConfiguration(
            holdDuration: holdDuration,
            moveTolerance: moveTolerance,
            requiredModifiers: requiredModifiers.rawValue
        )
    }
}
