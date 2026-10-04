import AppKit
import AVFoundation

/// The card shown after a recording is saved, in the spirit of the macOS
/// screenshot thumbnail: what was saved, where, how big and how long.
///
/// - Click the card to play the file in QuickTime Player. (The system default
///   for .m4a is Music, which would import the recording into the library.)
/// - Drag the thumbnail to drop the file into another app (a chat, a
///   transcription tool, Finder).
/// - **Show in Finder** reveals it; **×** closes the card.
///
/// It never takes focus, is left out of every capture (it belongs to our
/// process), and hides itself after a few seconds unless the pointer rests on it.
@MainActor
final class SavedRecordingCard {
    private static let size = NSSize(width: 384, height: 88)
    private static let margin: CGFloat = 16
    private static let linger: TimeInterval = 8

    /// Only one card at a time; a newer recording replaces the previous card.
    private static var current: SavedRecordingCard?

    private let panel: NSPanel
    private let view: CardView
    private var dismissWork: DispatchWorkItem?

    /// Shows the card for `fileURL`.
    /// - Parameters:
    ///   - anchor: Frame of the recording pill, in Cocoa screen coordinates.
    ///     The card takes the same corner, where the user's eye already is.
    ///   - screen: The screen the recording happened on.
    static func show(fileURL: URL, audioOnly: Bool, anchor: NSRect?, on screen: NSScreen) {
        current?.dismiss(animated: false)
        let card = SavedRecordingCard(fileURL: fileURL, audioOnly: audioOnly, anchor: anchor, screen: screen)
        current = card
        card.present()
    }

    private init(fileURL: URL, audioOnly: Bool, anchor: NSRect?, screen: NSScreen) {
        let origin = Self.origin(anchor: anchor, in: screen.visibleFrame)
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

        view = CardView(frame: NSRect(origin: .zero, size: Self.size), fileURL: fileURL, audioOnly: audioOnly)
        panel.contentView = view

        view.onOpen = { [weak self] in
            Self.play(fileURL)
            self?.dismiss(animated: true)
        }
        view.onReveal = { [weak self] in
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            self?.dismiss(animated: true)
        }
        view.onClose = { [weak self] in self?.dismiss(animated: true) }
        view.onHover = { [weak self] inside in
            if inside { self?.dismissWork?.cancel() } else { self?.scheduleDismiss() }
        }
    }

    /// Opens the file in QuickTime Player, falling back to the system default.
    private static func play(_ url: URL) {
        let workspace = NSWorkspace.shared
        if let player = workspace.urlForApplication(withBundleIdentifier: "com.apple.QuickTimePlayerX") {
            workspace.open([url], withApplicationAt: player, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
    }

    private func present() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        view.loadDetails()
        // The card usually appears right under the pointer (it replaces the pill
        // that was just clicked). Only start the countdown once the pointer is
        // elsewhere; leaving the card schedules it through the hover callback.
        if !panel.frame.contains(NSEvent.mouseLocation) {
            scheduleDismiss()
        }
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss(animated: true) }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: work)
    }

    private func dismiss(animated: Bool) {
        dismissWork?.cancel()
        dismissWork = nil
        let panel = panel
        let finish = { [weak self] in
            panel.orderOut(nil)
            if let self, Self.current === self { Self.current = nil }
        }
        guard animated else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }

    /// Same corner as the pill (left or right half, top or bottom half), else bottom-right.
    private static func origin(anchor: NSRect?, in visible: NSRect) -> NSPoint {
        let rightSide = anchor.map { $0.midX >= visible.midX } ?? true
        let bottomSide = anchor.map { $0.midY <= visible.midY } ?? true
        return NSPoint(
            x: rightSide ? visible.maxX - margin - size.width : visible.minX + margin,
            y: bottomSide ? visible.minY + margin : visible.maxY - margin - size.height
        )
    }
}

// MARK: - View

@MainActor
private final class CardView: NSView {
    var onOpen: (() -> Void)?
    var onReveal: (() -> Void)?
    var onClose: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    private let fileURL: URL
    private let audioOnly: Bool

    private let background = NSVisualEffectView()
    private let thumbnail: DraggableFileView
    private let titleLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let revealButton = FirstMouseButton(title: "Show in Finder", target: nil, action: nil)
    private let closeButton = FirstMouseButton(title: "", target: nil, action: nil)

    private var sizeText = ""
    private var durationText: String?

    init(frame: NSRect, fileURL: URL, audioOnly: Bool) {
        self.fileURL = fileURL
        self.audioOnly = audioOnly
        thumbnail = DraggableFileView(fileURL: fileURL)
        super.init(frame: frame)
        wantsLayer = true

        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        addSubview(background)

        // Thumbnail: a frame of the video, or a waveform for audio.
        thumbnail.frame = NSRect(x: 12, y: 12, width: 92, height: 64)
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 6
        thumbnail.layer?.masksToBounds = true
        thumbnail.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.toolTip = "Drag to use the file in another app"
        if audioOnly {
            let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
            thumbnail.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio recording")?
                .withSymbolConfiguration(config)
            thumbnail.contentTintColor = .white
            thumbnail.imageScaling = .scaleNone
        }
        thumbnail.onClick = { [weak self] in self?.onOpen?() }
        addSubview(thumbnail)

        let textX: CGFloat = 116
        let textWidth = bounds.width - textX - 34

        titleLabel.stringValue = audioOnly ? "Audio recording saved" : "Screen recording saved"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.frame = NSRect(x: textX, y: 58, width: textWidth, height: 18)
        addSubview(titleLabel)

        nameLabel.stringValue = fileURL.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.frame = NSRect(x: textX, y: 40, width: textWidth, height: 16)
        nameLabel.toolTip = fileURL.path
        addSubview(nameLabel)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingHead
        detailLabel.frame = NSRect(x: textX, y: 23, width: textWidth, height: 15)
        addSubview(detailLabel)

        revealButton.bezelStyle = .inline
        revealButton.controlSize = .small
        revealButton.font = .systemFont(ofSize: 11, weight: .medium)
        revealButton.target = self
        revealButton.action = #selector(reveal)
        revealButton.sizeToFit()
        revealButton.frame.origin = NSPoint(x: textX - 2, y: 3)
        addSubview(revealButton)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.frame = NSRect(x: bounds.width - 26, y: bounds.height - 26, width: 16, height: 16)
        addSubview(closeButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(titleLabel.stringValue): \(fileURL.lastPathComponent)")
        renderDetails()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Details

    /// Fills in size immediately, then duration and (for video) a thumbnail.
    func loadDetails() {
        if let bytes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            sizeText = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        renderDetails()

        let asset = AVURLAsset(url: fileURL)
        let audioOnly = audioOnly
        Task { @MainActor [weak self] in
            if let duration = try? await asset.load(.duration), duration.isNumeric {
                self?.durationText = Self.format(duration.seconds)
                self?.renderDetails()
            }
            guard !audioOnly else { return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 368, height: 256)
            if let (image, _) = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) {
                self?.thumbnail.image = NSImage(cgImage: image, size: .zero)
            }
        }
    }

    private func renderDetails() {
        let folder = (fileURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        detailLabel.stringValue = [folder, sizeText, durationText ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
        detailLabel.toolTip = fileURL.deletingLastPathComponent().path
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    // MARK: Interaction

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onOpen?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    @objc private func reveal() { onReveal?() }
    @objc private func close() { onClose?() }
}

/// Buttons in a non-activating panel must accept the first click.
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The thumbnail: click to open, drag to hand the file to another app.
@MainActor
private final class DraggableFileView: NSImageView, NSDraggingSource {
    var onClick: (() -> Void)?
    private let fileURL: URL
    private var pressEvent: NSEvent?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(frame: .zero)
        isEditable = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press = pressEvent else { return }
        pressEvent = nil
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: press, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressEvent = nil }
        guard pressEvent != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
