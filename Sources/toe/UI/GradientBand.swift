import AppKit
import ToeCore

/// The `col.active_border` gradient, drawn as a band around a rounded rectangle.
///
/// Extracted from `BorderOverlay` because three surfaces want the same gradient with the same
/// corner treatment: the focused window's outline, the quick menu panel's accent, and the theme
/// swatches in that menu. The subtleties below are each load-bearing and were worth not
/// reproducing three times.
final class GradientBand {

    let layer = CAGradientLayer()

    /// The gradient's mask. A plain `CALayer`, not a `CAShapeLayer`: only `CALayer` draws macOS's
    /// continuous-curvature corners, and a mask masks by whatever alpha it renders — so a layer
    /// with no background and a white border is exactly the band we want.
    private let band = CALayer()

    init() {
        layer.mask = band
        band.backgroundColor = nil                  // the middle stays transparent
        band.borderColor = NSColor.white.cgColor    // mask alpha only; the colour is the gradient's
        band.cornerCurve = .continuous              // macOS's squircle, not a circular arc
    }

    /// Colours and angle. Hyprland measures the gradient angle counter-clockwise from
    /// "left to right".
    func apply(start: String, end: String, angle: Double) {
        layer.colors = [Self.cgColor(start), Self.cgColor(end)]
        let radians = angle * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        layer.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
        layer.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
    }

    func apply(_ config: BorderConfig) {
        apply(start: config.activeStart, end: config.activeEnd, angle: config.angle)
    }

    /// `radius` is the *outer* radius of the band. `scale` is the target's backing scale factor —
    /// a mask rasterises at its own `contentsScale`, which defaults to 1, and without this the
    /// band is soft on Retina. It has to be re-read on every layout because the panel can move
    /// between displays.
    func layout(in bounds: CGRect, width: Double, radius: Double, scale: CGFloat) {
        layer.frame = bounds
        // `CALayer.borderWidth` draws inside the bounds, unlike a `CAShapeLayer` stroke, so the
        // band fills the whole outset with no half-line-width inset.
        band.frame = bounds
        band.borderWidth = width
        band.cornerRadius = radius
        if layer.contentsScale != scale { layer.contentsScale = scale }
        if band.contentsScale != scale { band.contentsScale = scale }
    }

    /// Parses `#RRGGBB` and `#RRGGBBAA` (Hyprland's `rgba()` ordering), falling back to the
    /// system accent so a typo in the config is visible rather than invisible.
    static func cgColor(_ hex: String) -> CGColor {
        guard let c = RGBA.parse(hex: hex) else { return NSColor.systemBlue.cgColor }
        return CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
