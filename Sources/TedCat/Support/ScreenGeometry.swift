import AppKit

/// Conversions between the two coordinate systems in play.
///
/// - **CG / global display space** (what `CGEvent.location`, `CGDisplayBounds`
///   and ScreenCaptureKit use): origin at the top-left of the primary display,
///   y grows downward.
/// - **Cocoa space** (what `NSScreen.frame` and `NSWindow` use): origin at the
///   bottom-left of the primary display, y grows upward.
///
/// Both share the same x axis and the same units (points), so a flip around
/// the primary display's height is all that is needed.
enum ScreenGeometry {
    /// The primary display is always `NSScreen.screens[0]` and has origin (0, 0).
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func cocoaPoint(fromCG point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func cocoaRect(fromCG rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The screen under a point given in CG space. Falls back to the main screen.
    static func screen(containingCG point: CGPoint) -> NSScreen? {
        let cocoa = cocoaPoint(fromCG: point)
        return NSScreen.screens.first { $0.frame.contains(cocoa) } ?? NSScreen.main
    }

    /// The active built-in display if there is one (laptop lid open), else the
    /// main display. Used when any display will do and staying connected matters.
    static func stableDisplayID() -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else {
            return CGMainDisplayID()
        }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
    }
}
