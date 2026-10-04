import AppKit
import HoldPickerCore

/// Orchestrates the whole pipeline: event tap → gesture recognizer → overlay →
/// screenshot to clipboard, or region recording to disk.
///
/// Everything runs on the main actor. The event tap callback, the hold timer and
/// the overlay all live on the main run loop, so there is no cross-thread state.
@MainActor
final class CaptureController {
    enum Status: Equatable {
        case active
        case disabled
        case needsAccessibility
    }

    private static let escapeKeyCode: Int64 = 53
    private static let minimumSelectionSize: CGFloat = 2
    private static let permissionRetryInterval: TimeInterval = 2

    private let preferences: Preferences
    let recording: RecordingController
    private let recognizer: HoldGestureRecognizer
    private var tap: EventTap?

    /// The mouse-down being held back while we wait to see if this is a hold.
    private var heldEvent: CGEvent?
    private var holdTimer: DispatchWorkItem?
    private var overlay: SelectionOverlayWindow?
    private var permissionRetryTimer: Timer?

    private(set) var status: Status = .disabled {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    var onStatusChange: ((Status) -> Void)?

    init(preferences: Preferences) {
        self.preferences = preferences
        self.recording = RecordingController(preferences: preferences)
        self.recognizer = HoldGestureRecognizer(configuration: preferences.gestureConfiguration)
    }

    /// Settings snapshot for the recognizer. One recording at a time: while a
    /// recording runs, the recording gesture is disabled but screenshots keep working.
    private var currentGestureConfiguration: HoldGestureConfiguration {
        var configuration = preferences.gestureConfiguration
        configuration.allowsRecording = !recording.isBusy
        return configuration
    }

    // MARK: - Lifecycle

    func start() {
        guard preferences.isEnabled else {
            status = .disabled
            return
        }

        // Ask for both grants up front so the user deals with them once.
        _ = Permissions.isAccessibilityTrusted(prompt: true)
        if !Permissions.hasScreenRecording {
            Permissions.requestScreenRecording()
        }

        startTapOrRetry()
    }

    func stop() {
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        resetGesture()
        tap?.stop()
        tap = nil
        status = .disabled
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func startTapOrRetry() {
        if tap == nil {
            tap = EventTap(
                events: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown],
                handler: { [weak self] type, event in
                    guard let self else { return Unmanaged.passUnretained(event) }
                    return self.handle(type: type, event: event)
                }
            )
            tap?.onReenabled = { [weak self] in
                Log.events.info("Event tap was disabled by the system; gesture reset")
                self?.resetGesture()
            }
        }

        do {
            try tap?.start()
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
            status = .active
            Log.events.info("Event tap started")
        } catch {
            if status != .needsAccessibility {
                Log.events.warning("Event tap unavailable, will retry: \(error.localizedDescription, privacy: .public)")
            }
            status = .needsAccessibility
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard permissionRetryTimer == nil else { return }
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: Self.permissionRetryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.preferences.isEnabled else { return }
                self.startTapOrRetry()
            }
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // Our own re-injected events must flow through untouched.
        if event.isSynthetic { return pass }

        if type == .keyDown {
            guard recognizer.isSelecting,
                  event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode
            else { return pass }
            apply(recognizer.handle(.cancel).effects)
            return nil
        }

        let input: PointerInput
        switch type {
        case .leftMouseDown:
            recognizer.configuration = currentGestureConfiguration
            input = .down(event.location, modifiers: event.flags.rawValue)
        case .leftMouseDragged:
            input = .drag(event.location)
        case .leftMouseUp:
            input = .up(event.location)
        default:
            return pass
        }

        let response = recognizer.handle(input)
        apply(response.effects)

        switch response.verdict {
        case .pass:
            return pass
        case .swallow:
            return nil
        case .hold:
            heldEvent = event.copy()
            return nil
        case .release:
            guard let held = heldEvent else { return pass }
            heldEvent = nil
            // Both go through the HID queue, which preserves their order.
            held.replay()
            event.replay()
            return nil
        }
    }

    private func apply(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .armTimer(let duration):
                armHoldTimer(after: duration)
            case .disarmTimer:
                holdTimer?.cancel()
                holdTimer = nil
            case .beginSelection(let origin, let mode):
                heldEvent = nil
                beginSelection(at: origin, mode: mode)
            case .updateSelection(let rect):
                overlay?.setSelection(cgRect: clamp(rect))
            case .commitSelection(let rect, let mode):
                commitSelection(clamp(rect), mode: mode)
            case .cancelSelection:
                dismissOverlay()
            }
        }
    }

    /// Abandons any gesture in progress. The held mouse-down is dropped, not
    /// replayed: its mouse-up may already have gone through, and replaying a
    /// lone mouse-down would leave the button stuck in the target app.
    private func resetGesture() {
        holdTimer?.cancel()
        holdTimer = nil
        heldEvent = nil
        dismissOverlay()
        recognizer.reset()
    }

    private func armHoldTimer(after duration: TimeInterval) {
        holdTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holdTimer = nil
                self.apply(self.recognizer.handle(.holdTimeout).effects)
            }
        }
        holdTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    // MARK: - Selection

    private func beginSelection(at origin: CGPoint, mode: CaptureMode) {
        dismissOverlay()
        guard let screen = ScreenGeometry.screen(containingCG: origin) else { return }
        let window = SelectionOverlayWindow(screen: screen, mode: mode)
        window.setSelection(cgRect: CGRect(origin: origin, size: .zero))
        window.show()
        overlay = window
        Log.capture.debug("Selection started at \(origin.x, privacy: .public),\(origin.y, privacy: .public)")
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        guard let overlay else { return rect }
        return rect.clamped(to: overlay.cgFrame)
    }

    private func commitSelection(_ rect: CGRect, mode: CaptureMode) {
        guard let overlay else { return }
        self.overlay = nil

        guard rect.width >= Self.minimumSelectionSize, rect.height >= Self.minimumSelectionSize else {
            overlay.dismiss()
            Log.capture.debug("Selection too small, ignored")
            return
        }

        switch mode {
        case .screenshot:
            takeScreenshot(rect, overlay: overlay)
        case .recording:
            overlay.dismiss()
            recording.start(rect: rect, on: overlay.targetScreen)
        }
    }

    private func takeScreenshot(_ rect: CGRect, overlay: SelectionOverlayWindow) {
        let displayID = ScreenGeometry.displayID(of: overlay.targetScreen)

        // The flash gives instant feedback while the capture runs. All of our
        // windows are excluded from the capture, so it never shows in the result.
        overlay.flashThenDismiss()

        Task { @MainActor [preferences] in
            do {
                let image = try await ScreenCapturer.capture(rect: rect, displayID: displayID)
                Clipboard.write(image, pointSize: rect.size)
                if preferences.playsSound {
                    NSSound(named: "Pop")?.play()
                }
                Log.capture.info("Captured \(Int(rect.width))×\(Int(rect.height)) pt to clipboard")
            } catch {
                Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func dismissOverlay() {
        overlay?.dismiss()
        overlay = nil
    }
}
