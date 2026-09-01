import Foundation

/// The corner-radius arithmetic behind the focus border. Lives in ToeCore, away from AppKit,
/// so the selftest can reach it — the pixels themselves can only be eyeballed.
public enum BorderGeometry {

    /// The radius of the *window's own* corner. A negative `configured` follows the system.
    ///
    /// Clamped to half the shorter side: Core Animation would clamp it silently anyway, and a
    /// radius larger than that is meaningless. Clamping against the window box rather than the
    /// outset one is still enough for `outerRadius`, since `(min + 2w) / 2 >= min / 2 + w`.
    public static func effectiveRadius(configured: Double, system: Double, box: Box) -> Double {
        let base = configured < 0 ? system : configured
        return max(0, min(base, min(box.w, box.h) / 2))
    }

    /// The radius the band is drawn with. The band sits `width` points outside the window, and
    /// the outward offset of a curve of radius `inner` has radius `inner + width` — which is
    /// what lands the band's inner edge exactly on the window's own corner.
    public static func outerRadius(inner: Double, width: Double) -> Double {
        max(0, inner) + max(0, width)
    }

    /// The rectangle the band is drawn in: the window grown by the band's width on every side.
    /// The band is the ring between this and `box`, so it never covers the window itself.
    public static func outset(_ box: Box, by width: Double) -> Box {
        let w = max(0, width)
        return Box(x: box.x - w, y: box.y - w, w: box.w + 2 * w, h: box.h + 2 * w)
    }

    /// Whether anything in `others` covers part of the *band*, rather than merely sitting over
    /// the window's own interior — which the border never draws on anyway, so a dialog centred
    /// on the window hides none of it.
    ///
    /// `epsilon` decides how much overlap counts, and leans towards "not covered": a window
    /// clipping the band by a fraction of a point is rounding noise between Accessibility's
    /// idea of a frame and the window server's, not something anyone can see.
    public static func bandIsCovered(window: Box, width: Double,
                                     by others: [Box], epsilon: Double = 0.5) -> Bool {
        guard width > 0 else { return false }
        let outer = outset(window, by: width)
        return others.contains { other in
            let clipped = outer.intersection(other)
            // This guard has to come first. `Box.intersection` clamps the *size* to zero for
            // boxes that miss each other, but leaves the origin at `max(minX, other.minX)` —
            // which for a disjoint box sits outside the window, and would read below as the
            // band being covered.
            guard clipped.w > 0, clipped.h > 0 else { return false }
            // Inside the hole covers nothing. Sticking out of it on any side covers the band.
            let out = max(window.minX - clipped.minX, clipped.maxX - window.maxX,
                          window.minY - clipped.minY, clipped.maxY - window.maxY)
            return out > epsilon
        }
    }
}
