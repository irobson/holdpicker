import CoreGraphics
import ScreenCaptureKit

/// Grabs a region of one display as a `CGImage` using ScreenCaptureKit.
enum ScreenCapturer {
    enum Error: Swift.Error, LocalizedError {
        case displayNotFound(CGDirectDisplayID)

        var errorDescription: String? {
            switch self {
            case .displayNotFound(let id):
                return "Display \(id) is not available for capture."
            }
        }
    }

    /// - Parameters:
    ///   - rect: Region in global display (CG) coordinates, in points.
    ///   - displayID: The display the region belongs to. Must contain `rect`.
    ///   - excludingWindowIDs: Windows to leave out of the capture (our overlay).
    /// - Returns: A full-resolution image (points × backing scale).
    static func capture(
        rect: CGRect,
        displayID: CGDirectDisplayID,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Error.displayNotFound(displayID)
        }

        let excluded = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let scale = CGFloat(filter.pointPixelScale)

        let configuration = SCStreamConfiguration()
        // sourceRect is relative to the display's own top-left corner.
        configuration.sourceRect = CGRect(
            x: rect.minX - display.frame.minX,
            y: rect.minY - display.frame.minY,
            width: rect.width,
            height: rect.height
        )
        configuration.width = Int((rect.width * scale).rounded())
        configuration.height = Int((rect.height * scale).rounded())
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
