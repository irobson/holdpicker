import AppKit
import QuartzCore

/// Draws the dimmed backdrop, the selection frame and the size label.
///
/// Everything is a `CALayer`, so updating the selection only moves a handful of
/// layer frames; nothing is re-rasterised on each mouse move.
@MainActor
final class SelectionOverlayView: NSView {
    private enum Style {
        static let dimColor = NSColor.black.withAlphaComponent(0.35).cgColor
        static let borderColor = NSColor.white.cgColor
        static let outlineColor = NSColor.black.withAlphaComponent(0.5).cgColor
        static let labelBackground = NSColor.black.withAlphaComponent(0.7).cgColor
        static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        static let labelPadding: CGFloat = 6
        static let labelGap: CGFloat = 8
        static let flashDuration: CFTimeInterval = 0.18
    }

    /// Selection in this view's (Cocoa, bottom-left origin) coordinates.
    var selection: CGRect? {
        didSet { layoutLayers() }
    }

    private let dimLayers: [CALayer] = (0..<4).map { _ in CALayer() }
    private let outlineLayer = CALayer()
    private let borderLayer = CALayer()
    private let labelLayer = CATextLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor

        for dim in dimLayers {
            dim.backgroundColor = Style.dimColor
            layer?.addSublayer(dim)
        }

        outlineLayer.borderColor = Style.outlineColor
        outlineLayer.borderWidth = 1
        layer?.addSublayer(outlineLayer)

        borderLayer.borderColor = Style.borderColor
        borderLayer.borderWidth = 1
        layer?.addSublayer(borderLayer)

        labelLayer.font = Style.labelFont
        labelLayer.fontSize = Style.labelFont.pointSize
        labelLayer.foregroundColor = NSColor.white.cgColor
        labelLayer.backgroundColor = Style.labelBackground
        labelLayer.cornerRadius = 4
        labelLayer.alignmentMode = .center
        labelLayer.isHidden = true
        layer?.addSublayer(labelLayer)

        layoutLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        labelLayer.contentsScale = scale
    }

    // MARK: - Layout

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let selection, !selection.isEmpty else {
            // No selection yet: dim everything, hide the frame.
            dimLayers[0].frame = bounds
            for dim in dimLayers.dropFirst() { dim.frame = .zero }
            outlineLayer.frame = .zero
            borderLayer.frame = .zero
            labelLayer.isHidden = true
            return
        }

        // Four rectangles around the selection leave a clear hole in the middle.
        dimLayers[0].frame = CGRect(x: 0, y: selection.maxY, width: bounds.width, height: bounds.maxY - selection.maxY)
        dimLayers[1].frame = CGRect(x: 0, y: 0, width: bounds.width, height: selection.minY)
        dimLayers[2].frame = CGRect(x: 0, y: selection.minY, width: selection.minX, height: selection.height)
        dimLayers[3].frame = CGRect(x: selection.maxX, y: selection.minY, width: bounds.maxX - selection.maxX, height: selection.height)

        borderLayer.frame = selection
        outlineLayer.frame = selection.insetBy(dx: -1, dy: -1)

        layoutLabel(for: selection)
    }

    private func layoutLabel(for selection: CGRect) {
        let text = "\(Int(selection.width.rounded())) × \(Int(selection.height.rounded()))"
        labelLayer.string = text

        let textSize = (text as NSString).size(withAttributes: [.font: Style.labelFont])
        let size = CGSize(
            width: ceil(textSize.width) + Style.labelPadding * 2,
            height: ceil(textSize.height) + Style.labelPadding
        )

        // Prefer below the selection; go above when there is no room; fall
        // back to inside the selection when the frame is nearly full-screen.
        var origin = CGPoint(x: selection.midX - size.width / 2, y: selection.minY - Style.labelGap - size.height)
        if origin.y < 0 {
            origin.y = selection.maxY + Style.labelGap
        }
        if origin.y + size.height > bounds.maxY {
            origin.y = selection.minY + Style.labelGap
        }
        origin.x = min(max(origin.x, 0), bounds.maxX - size.width)

        labelLayer.frame = CGRect(origin: origin, size: size)
        labelLayer.isHidden = false
    }

    // MARK: - Feedback

    /// Briefly flashes the selected area white, then calls `completion`.
    func playCaptureFlash(completion: @escaping () -> Void) {
        guard let selection, !selection.isEmpty, let hostLayer = layer else {
            completion()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for dim in dimLayers { dim.isHidden = true }
        labelLayer.isHidden = true
        CATransaction.commit()

        let flash = CALayer()
        flash.frame = selection
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0.7
        hostLayer.addSublayer(flash)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7
        fade.toValue = 0
        fade.duration = Style.flashDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            flash.removeFromSuperlayer()
            completion()
        }
        flash.add(fade, forKey: "flash")
        CATransaction.commit()
    }
}
