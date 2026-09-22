import CoreGraphics
import Foundation

public extension CGPoint {
    /// Euclidean distance to another point.
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
}

public extension CGRect {
    /// Builds a normalized rectangle from two opposite corners, in any order.
    init(corner a: CGPoint, opposite b: CGPoint) {
        self.init(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    /// Clamps the rectangle so it lies entirely inside `bounds`.
    /// Returns `.zero` when there is no overlap.
    func clamped(to bounds: CGRect) -> CGRect {
        let result = intersection(bounds)
        return result.isNull ? .zero : result
    }
}
