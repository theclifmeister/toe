import AppKit

/// toe's own mark: the crossbar and stem of the app icon's T, without the tile under it.
///
/// Drawn rather than scaled down from `Toe.icns`, for two reasons. A template image is made
/// from its alpha, and the icon's alpha is the whole rounded square — as a menu bar template
/// it would be a solid blob. And the proportions here are the icon's own, read off
/// `scripts/make-icon.swift`, so the two stay one design rather than two drawings of it.
///
/// The gutter goes, as it does in that script under 128px: a gap a quarter of a pixel wide
/// is grey mud rather than a seam. The stem thickening that goes with it there does *not*,
/// though — it exists to hold the stem up against a crossbar sitting on a tile, and here
/// there is no tile and the neighbours are light digits, where a stem half again as wide as
/// the crossbar reads as a different weight of type. Dropped, the two strokes come out equal,
/// which is what the icon's own proportions ask for at every size that can afford them.
///
/// One drawing, two places: the menu bar item leads its strip with it, and the bar's menu
/// widget is it — where Omarchy draws its logo glyph, toe draws its T.
enum ToeMark {

    /// The T's bounding box in `scripts/make-icon.swift` is `tWidth` by `tHeight` of the icon's
    /// shape, so the mark keeps that proportion rather than being squared off.
    static func width(forHeight height: CGFloat) -> CGFloat { snap(height * 0.52 / 0.60) }

    /// Half a point, which is a whole pixel on every display toe supports. Strokes two points
    /// wide have to land on the grid or they render as three grey ones.
    static func snap(_ value: CGFloat) -> CGFloat { (value * 2).rounded() / 2 }

    /// Fills the T into `rect`, in `colour`, in whatever coordinate system the caller is drawing
    /// in — the crossbar goes at `maxY`, which is the top in an unflipped image and the bottom
    /// in a flipped view, so a flipped caller hands in a rect whose `maxY` is its top.
    static func draw(in rect: NSRect, colour: NSColor, flipped: Bool = false) {
        colour.setFill()
        let crossbarHeight = snap(rect.height * 0.24)
        let stemWidth = snap(rect.width * 0.28)
        let radius: CGFloat = 0.5
        let crossbarY = flipped ? rect.minY : rect.maxY - crossbarHeight
        let stemY = flipped ? rect.minY + crossbarHeight : rect.minY
        let crossbar = NSRect(x: rect.minX, y: crossbarY, width: rect.width, height: crossbarHeight)
        let stem = NSRect(x: snap(rect.midX - stemWidth / 2), y: stemY,
                          width: stemWidth, height: rect.height - crossbarHeight)
        NSBezierPath(roundedRect: crossbar, xRadius: radius, yRadius: radius).fill()
        NSBezierPath(roundedRect: stem, xRadius: radius, yRadius: radius).fill()
    }
}
