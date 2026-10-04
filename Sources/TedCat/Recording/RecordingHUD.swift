import AppKit

/// The small floating pill shown while recording.
///
/// It sits in the screen corner farthest from the recorded region, never takes
/// focus, and is left out of the video. Clicking it stops the recording. Once
/// the file is written it gives way to `SavedRecordingCard`; failures stay on
/// the pill for a few seconds.
@MainActor
final class RecordingHUD {
    private static let size = NSSize(width: 132, height: 34)
    private static let margin: CGFloat = 16
    private static let lingerAfterSave: TimeInterval = 4

    var onStop: (() -> Void)?

    private let panel: NSPanel
    private let content: HUDView
    private var ticker: Timer?
    private var dismissWork: DispatchWorkItem?

    /// The pill's frame in screen coordinates, so the saved card can take its corner.
    var frame: NSRect { panel.frame }

    /// - Parameter audioOnly: Shows a waveform instead of the red dot while recording.
    init(avoiding region: CGRect, on screen: NSScreen, audioOnly: Bool = false) {
        let origin = Self.corner(avoiding: region, in: screen.visibleFrame)
        panel = NSPanel(
            contentRect: NSRect(origin: origin, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        content = HUDView(frame: NSRect(origin: .zero, size: Self.size), audioOnly: audioOnly)
        panel.contentView = content
        content.onClick = { [weak self] in self?.handleClick() }
    }

    // MARK: - States

    func showRecording(since start: Date) {
        content.render(.recording(elapsed: 0))
        panel.orderFrontRegardless()

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.content.render(.recording(elapsed: Date().timeIntervalSince(start)))
            }
        }
    }

    func showSaving() {
        ticker?.invalidate()
        ticker = nil
        content.render(.saving)
    }

    /// Hides the pill right away (the saved card takes over).
    func dismissNow() {
        dismiss()
    }

    func showFailure(_ message: String) {
        content.render(.failed)
        content.toolTip = message
        scheduleDismiss()
    }

    /// A standalone error pill for failures before a recording ever started.
    static func flashFailure(_ message: String) {
        guard let screen = NSScreen.main else { return }
        let hud = RecordingHUD(avoiding: .zero, on: screen)
        hud.panel.orderFrontRegardless()
        hud.showFailure(message)
    }

    private var retainUntilDismissed: RecordingHUD?

    // MARK: - Interaction

    private func handleClick() {
        if ticker != nil {
            onStop?()
        }
    }

    private func scheduleDismiss() {
        // The owner lets go of the HUD after saving; keep it alive until it hides itself.
        retainUntilDismissed = self
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerAfterSave, execute: work)
    }

    private func dismiss() {
        ticker?.invalidate()
        ticker = nil
        dismissWork?.cancel()
        panel.orderOut(nil)
        retainUntilDismissed = nil
    }

    // MARK: - Placement

    /// Picks the corner of `visible` whose HUD frame is farthest from the region's center.
    private static func corner(avoiding region: CGRect, in visible: NSRect) -> NSPoint {
        let left = visible.minX + margin
        let right = visible.maxX - margin - size.width
        let bottom = visible.minY + margin
        let top = visible.maxY - margin - size.height

        let candidates = [
            NSPoint(x: right, y: bottom),
            NSPoint(x: left, y: bottom),
            NSPoint(x: right, y: top),
            NSPoint(x: left, y: top),
        ]
        guard !region.isEmpty else { return candidates[0] }

        let center = CGPoint(x: region.midX, y: region.midY)
        return candidates.max { a, b in
            let ca = CGPoint(x: a.x + size.width / 2, y: a.y + size.height / 2)
            let cb = CGPoint(x: b.x + size.width / 2, y: b.y + size.height / 2)
            return hypot(ca.x - center.x, ca.y - center.y) < hypot(cb.x - center.x, cb.y - center.y)
        } ?? candidates[0]
    }
}

// MARK: - View

@MainActor
private final class HUDView: NSView {
    enum Content: Equatable {
        case recording(elapsed: TimeInterval)
        case saving
        case failed
    }

    var onClick: (() -> Void)?

    private let audioOnly: Bool
    private let background = NSVisualEffectView()
    private let dot = CALayer()
    private let waveform = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let stopGlyph = NSImageView()

    init(frame: NSRect, audioOnly: Bool) {
        self.audioOnly = audioOnly
        super.init(frame: frame)
        wantsLayer = true

        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = bounds.height / 2
        background.layer?.masksToBounds = true
        addSubview(background)

        let dotSize: CGFloat = 10
        dot.frame = CGRect(x: 14, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = NSColor.systemRed.cgColor
        layer?.addSublayer(dot)

        waveform.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        waveform.contentTintColor = .systemRed
        waveform.frame = NSRect(x: 10, y: (bounds.height - 16) / 2, width: 18, height: 16)
        waveform.wantsLayer = true
        waveform.isHidden = true
        addSubview(waveform)

        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.frame = NSRect(x: 32, y: (bounds.height - 18) / 2, width: 64, height: 18)
        addSubview(label)

        stopGlyph.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop recording")
        stopGlyph.contentTintColor = .labelColor
        stopGlyph.frame = NSRect(x: bounds.width - 32, y: (bounds.height - 16) / 2, width: 16, height: 16)
        addSubview(stopGlyph)

        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Claim the press so AppKit routes the matching mouse-up here.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func render(_ content: Content) {
        if case .recording = content {} else {
            pulsingLayer?.removeAnimation(forKey: "pulse")
            waveform.isHidden = true
            dot.isHidden = false
        }
        switch content {
        case .recording(let elapsed):
            dot.backgroundColor = NSColor.systemRed.cgColor
            dot.isHidden = audioOnly
            waveform.isHidden = !audioOnly
            stopGlyph.isHidden = false
            stopGlyph.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop recording")
            label.stringValue = Self.format(elapsed)
            let what = audioOnly ? "Recording audio" : "Recording"
            setAccessibilityLabel("\(what) \(Self.format(elapsed)). Click to stop.")
            addPulse()
        case .saving:
            dot.backgroundColor = NSColor.systemOrange.cgColor
            stopGlyph.isHidden = true
            label.stringValue = "Saving…"
            setAccessibilityLabel("Saving recording")
        case .failed:
            dot.backgroundColor = NSColor.systemYellow.cgColor
            stopGlyph.isHidden = true
            label.stringValue = "Failed"
            setAccessibilityLabel("Recording failed")
        }
    }

    /// The red dot for video recordings, the waveform for audio-only ones.
    private var pulsingLayer: CALayer? {
        audioOnly ? waveform.layer : dot
    }

    private func addPulse() {
        guard let target = pulsingLayer, target.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        target.add(pulse, forKey: "pulse")
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
