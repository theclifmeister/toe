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
}
