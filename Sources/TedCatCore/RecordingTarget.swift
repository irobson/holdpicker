import CoreGraphics
import Foundation

/// What a recording captures.
///
/// The Shift + hold gesture only ever records a dragged region; audio-only
/// recordings are started from the menu bar menu. A drag that is too small or
/// too thin for the video encoder is reported as such, so the release can be
/// ignored instead of failing later.
public enum RecordingTarget: Equatable, Sendable {
    /// System audio only, saved as M4A. Started from the menu, never by the gesture.
    case audioOnly
    /// Video of the region (global CG coordinates, points) plus system audio, saved as MP4.
    case region(CGRect)
    /// The selection is below what the encoder accepts (including no drag at all).
    case tooSmall

    /// Below this size on *both* axes, in points, the user has not really
    /// dragged yet. The overlay uses it to show a hint instead of "too small".
    public static let dragThreshold: CGFloat = 10

    /// The target for a dragged selection: a region if it can be filmed, else `.tooSmall`.
    /// - Parameters:
    ///   - selection: The dragged rectangle, in points.
    ///   - scale: Backing scale factor of the display (2 on Retina).
    public init(selection: CGRect, scale: CGFloat) {
        if VideoEncodingPlan(pointSize: selection.size, scale: scale) != nil {
            self = .region(selection)
        } else {
            self = .tooSmall
        }
    }

    /// True while the selection is still below the drag threshold on both axes.
    public static func isUndragged(_ selection: CGRect) -> Bool {
        selection.width < dragThreshold && selection.height < dragThreshold
    }

    public var isAudioOnly: Bool { self == .audioOnly }
}
