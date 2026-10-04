import Foundation
import ScreenCaptureKit

/// Builds the ScreenCaptureKit filter shared by screenshots and recordings.
enum CaptureFilter {
    enum Error: Swift.Error, LocalizedError {
        case displayNotFound(CGDirectDisplayID)

        var errorDescription: String? {
            switch self {
            case .displayNotFound(let id):
                return "Display \(id) is not available for capture."
            }
        }
    }

    /// A filter for one display that leaves out every window TedCat owns:
    /// the selection overlay, the recording frame and the recording controls.
    /// That keeps our own UI out of both screenshots and videos.
    static func display(_ displayID: CGDirectDisplayID) async throws -> (SCContentFilter, SCDisplay) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Error.displayNotFound(displayID)
        }

        // Match by PID, not bundle ID, so it also works when run unbundled (`swift run`).
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }

        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        return (filter, display)
    }

    /// Converts a rectangle in global CG coordinates into the display-relative
    /// rectangle that `SCStreamConfiguration.sourceRect` expects.
    static func sourceRect(for rect: CGRect, on display: SCDisplay) -> CGRect {
        CGRect(
            x: rect.minX - display.frame.minX,
            y: rect.minY - display.frame.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
