import AppKit
import HoldPickerCore

/// A transparent, click-through window covering one screen while the user
/// drags out a selection. Mouse input never reaches it: the event tap owns
/// the pointer and feeds coordinates in from outside.
@MainActor
final class SelectionOverlayWindow: NSWindow {
    let targetScreen: NSScreen
    /// The screen's frame in CG (top-left origin) coordinates.
    let cgFrame: CGRect
    private let overlayView: SelectionOverlayView

    let mode: CaptureMode

    init(screen: NSScreen, mode: CaptureMode) {
        targetScreen = screen
        self.mode = mode
        cgFrame = ScreenGeometry.cgRect(fromCocoa: screen.frame)
        overlayView = SelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), mode: mode)

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = overlayView
    }

    func show() {
        orderFrontRegardless()
    }

    /// Sets the selection from a rectangle in CG coordinates.
    func setSelection(cgRect: CGRect) {
        let cocoa = ScreenGeometry.cocoaRect(fromCG: cgRect)
        overlayView.selection = cocoa.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    func flashThenDismiss() {
        overlayView.playCaptureFlash { [weak self] in
            self?.dismiss()
        }
    }

    func dismiss() {
        orderOut(nil)
    }
}
