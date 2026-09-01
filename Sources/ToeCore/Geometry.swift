import Foundation

/// Window identity. Matches `CGWindowID` but keeps ToeCore free of CoreGraphics.
public typealias WindowID = UInt32

public struct Point: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// An axis-aligned rectangle in Accessibility coordinates: origin top-left of the
/// primary display, y growing downward. Port of Hyprland's `CBox`.
public struct Box: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var middle: Point { Point(x: x + w / 2.0, y: y + h / 2.0) }

    /// `CBox::noNegativeSize()`
    public func noNegativeSize() -> Box {
        Box(x: x, y: y, w: max(0, w), h: max(0, h))
    }

    /// `CBox::round()` — Hyprland rounds before handing a box to a window to avoid
    /// sub-pixel drift accumulating down the tree.
    public func rounded() -> Box {
        Box(x: x.rounded(), y: y.rounded(), w: w.rounded(), h: h.rounded())
    }

    public func contains(_ p: Point) -> Bool {
        p.x >= x && p.x < maxX && p.y >= y && p.y < maxY
    }

    /// Hyprland's `vecToRectDistanceSquared` — zero when the point is inside the box.
    public func distanceSquared(to p: Point) -> Double {
        let dx = max(0.0, minX - p.x, p.x - maxX)
        let dy = max(0.0, minY - p.y, p.y - maxY)
        return dx * dx + dy * dy
    }

    /// The overlapping region of two boxes, empty when they do not overlap. How much of a
    /// floating window is actually on its monitor is measured with this.
    public func intersection(_ other: Box) -> Box {
        Box(x: max(minX, other.minX),
            y: max(minY, other.minY),
            w: min(maxX, other.maxX) - max(minX, other.minX),
            h: min(maxY, other.maxY) - max(minY, other.minY)).noNegativeSize()
    }

    /// Shrink by per-edge insets. Used to apply gaps.
    public func inset(top: Double, left: Double, bottom: Double, right: Double) -> Box {
        Box(x: x + left, y: y + top, w: w - left - right, h: h - top - bottom).noNegativeSize()
    }
}

/// Hyprland's `STICKS(a, b)`: two coordinates are "the same edge" within 2px.
/// This is what makes directional focus adjacency-based rather than nearest-center.
@inlinable
public func STICKS(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < 2.0
}

@inlinable
public func clampf(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(v, lo), hi)
}
