import CoreGraphics
import Foundation

/// Output size and bitrate for a region recording.
///
/// Tuned for screen content that must stay legible (code, documents, slides,
/// subtitles) while keeping files small: native pixel density, 30 fps, and a
/// bitrate proportional to the pixel rate, clamped to a sane range.
public struct VideoEncodingPlan: Equatable, Sendable {
    public static let framesPerSecond = 30
    /// Bits per pixel per frame. HEVC on screen content stays sharp well below 0.1.
    public static let bitsPerPixel = 0.04
    public static let minimumBitrate = 1_500_000
    public static let maximumBitrate = 6_000_000
    /// Encoders need a few macroblocks to work with.
    public static let minimumPixelSide = 32

    public let pixelWidth: Int
    public let pixelHeight: Int
    public let averageBitrate: Int

    /// - Parameters:
    ///   - pointSize: Region size in points.
    ///   - scale: Backing scale factor of the display (2 on Retina).
    /// - Returns: `nil` when the region is too small to encode.
    public init?(pointSize: CGSize, scale: CGFloat) {
        // H.264/HEVC need even dimensions (4:2:0 chroma subsampling).
        let width = Self.even(pointSize.width * scale)
        let height = Self.even(pointSize.height * scale)
        guard width >= Self.minimumPixelSide, height >= Self.minimumPixelSide else { return nil }

        let raw = Double(width * height * Self.framesPerSecond) * Self.bitsPerPixel
        pixelWidth = width
        pixelHeight = height
        averageBitrate = min(max(Int(raw), Self.minimumBitrate), Self.maximumBitrate)
    }

    private static func even(_ value: CGFloat) -> Int {
        let rounded = Int(value.rounded())
        return rounded - rounded % 2
    }
}
