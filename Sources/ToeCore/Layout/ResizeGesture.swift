import Foundation

/// The arithmetic of a mouse resize, kept out of `Sources/toe` for the reason `BorderGeometry`
/// is: the frame is read through Accessibility and the tile comes from the coordinator, but
/// what the two say together is geometry, and geometry can be tested.
public enum ResizeGesture {

    /// Which edges moved between the tile a drag started from and the frame it let go with, and
    /// how far each went.
    ///
    /// Edges are compared as edges, not as origin plus size: a left-edge drag changes both `x`
    /// and `w` while leaving `maxX` alone, and it is the left edge that moved. `dx` and `dy` are
    /// the displacement of the edge that moved, positive right and down — the pointer delta
    /// `DwindleLayout.resizeActive` expects — and deliberately *not* the change in width, which
    /// is the obvious wrong answer: pulling the left edge outwards makes the window wider and
    /// gives a negative `dx`.
    ///
    /// An axis counts as resized only when the size along it changed by `tolerance` — the 2pt
    /// the coordinator's `settled` allows an app for its own rounding. Both edges moving by the
    /// same amount is a move, not a resize, and a drag that was taken for a resize because a
    /// Resized notification arrived can still be one: that axis is left out, and if neither is
    /// left the answer is nil and the window snaps back to its tile as it always did. When the
    /// size did change, the edge that travelled further is the one in the user's hand.
    public static func delta(from origin: Box, to final: Box, tolerance: Double = 2.0)
        -> (edges: ResizeEdges, dx: Double, dy: Double)? {
        var edges: ResizeEdges = []
        var dx = 0.0
        var dy = 0.0

        let left = final.minX - origin.minX
        let right = final.maxX - origin.maxX
        if abs(right - left) >= tolerance {
            if abs(right) >= abs(left) { edges.insert(.right); dx = right }
            else                       { edges.insert(.left);  dx = left }
        }

        let top = final.minY - origin.minY
        let bottom = final.maxY - origin.maxY
        if abs(bottom - top) >= tolerance {
            if abs(bottom) >= abs(top) { edges.insert(.bottom); dy = bottom }
            else                       { edges.insert(.top);    dy = top }
        }

        return edges.isEmpty ? nil : (edges, dx, dy)
    }
}
