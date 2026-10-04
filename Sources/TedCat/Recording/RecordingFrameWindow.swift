import AppKit

/// A thin red outline drawn just *outside* the region being recorded, so the
/// user always knows what is on tape. Click-through, on all Spaces, and
/// excluded from the capture itself (it belongs to our process).
@MainActor
final class RecordingFrameWindow: NSWindow {
    private static let lineWidth: CGFloat = 2

    init(cgRect: CGRect) {
        let inner = ScreenGeometry.cocoaRect(fromCG: cgRect)
        let outer = inner.insetBy(dx: -Self.lineWidth, dy: -Self.lineWidth)

        super.init(contentRect: outer, styleMask: .borderless, backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: outer.size))
        view.wantsLayer = true
        let border = CAShapeLayer()
        let path = CGPath(
            rect: view.bounds.insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2),
            transform: nil
        )
        border.path = path
        border.fillColor = nil
        border.strokeColor = NSColor.systemRed.cgColor
        border.lineWidth = Self.lineWidth
        border.lineDashPattern = [6, 4]
        view.layer?.addSublayer(border)
        contentView = view
    }

    func show() {
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}
