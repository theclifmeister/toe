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

    /// Whether `window` sits on a display a fullscreen window has taken over.
    ///
    /// The border panel is `.canJoinAllSpaces` with `.fullScreenAuxiliary` — deliberately, so
    /// the ring survives the Space it sits on being switched away and back — which is also
    /// what lets it paint a tiled window's outline straight across a fullscreen Space. This
    /// is the test that stops it.
    ///
    /// Geometry rather than a global "is anything fullscreen" flag, because under macOS's
    /// default *Displays have separate Spaces* both are true at once: a fullscreen Safari on
    /// the second display leaves the first showing its ordinary Space, tiled windows and all,
    /// and the ring there is covering nothing. A fullscreen window fills exactly one display,
    /// so overlapping its frame is the same question as sharing its display.
    ///
    /// Measured against the window rather than the band drawn around it. The band is outset
    /// past the window's edges, so a tile flush against the boundary between two displays
    /// would bleed its border width into the neighbouring one and read as covered there —
    /// the window itself never does.
    ///
    /// `epsilon` leans the same way `bandIsCovered` does: a sliver of overlap is the window
    /// server and Accessibility disagreeing about an edge, not a shared display.
    public static func isBehindFullscreen(window: Box, fullscreen: Box?,
                                          epsilon: Double = 1) -> Bool {
        guard let fullscreen else { return false }
        let clipped = window.intersection(fullscreen)
        return clipped.w > epsilon && clipped.h > epsilon
    }

    /// The display one of `windows` covers edge to edge, or nil when none does — the
    /// fullscreen that `AXFullScreen` never hears of (T9). A game that skips native fullscreen
    /// opens a borderless window the size of the display, or keeps resizing a standard one back
    /// to it after toe has tiled it, or captures the display and draws at the shielding level;
    /// none of those is a fullscreen window to Accessibility, and each is one the user is
    /// looking at the whole display through. The rule is the user's: a focused application
    /// filling its display gets no border, native or not.
    ///
    /// "Covers" is contains, not overlaps: a tile already fills its display's usable area,
    /// and the menu bar's strip (or the bar's) is what keeps it from reading as fullscreen.
    /// A window larger than the display — a game that leaves its title bar above the top edge —
    /// still covers it. `epsilon` forgives the half-point a scaled display rounds an edge to.
    ///
    /// The display's frame comes back rather than the window's, so that `isBehindFullscreen`
    /// scopes the answer exactly as it does a native fullscreen window: an oversized window
    /// spilling a few points onto the neighbouring display has not taken that one over. A
    /// window spanning two displays answers with the first; the border only needs one.
    public static func coveredDisplay(by windows: [Box], among displays: [Box],
                                      epsilon: Double = 1) -> Box? {
        displays.first { display in
            windows.contains { window in
                window.minX <= display.minX + epsilon && window.maxX >= display.maxX - epsilon
                    && window.minY <= display.minY + epsilon && window.maxY >= display.maxY - epsilon
            }
        }
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
