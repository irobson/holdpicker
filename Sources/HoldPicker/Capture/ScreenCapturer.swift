import CoreGraphics
import ScreenCaptureKit

/// Grabs a region of one display as a `CGImage` using ScreenCaptureKit.
enum ScreenCapturer {
    /// - Parameters:
    ///   - rect: Region in global display (CG) coordinates, in points.
    ///   - displayID: The display the region belongs to. Must contain `rect`.
    /// - Returns: A full-resolution image (points × backing scale).
    static func capture(rect: CGRect, displayID: CGDirectDisplayID) async throws -> CGImage {
        let (filter, display) = try await CaptureFilter.display(displayID)
        let scale = CGFloat(filter.pointPixelScale)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CaptureFilter.sourceRect(for: rect, on: display)
        configuration.width = Int((rect.width * scale).rounded())
        configuration.height = Int((rect.height * scale).rounded())
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
