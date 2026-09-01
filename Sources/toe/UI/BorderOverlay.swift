import AppKit
import ToeCore

/// A click-through panel that outlines the focused window, reproducing Omarchy's
/// `col.active_border` gradient. Repositioned on focus and layout changes only — there is
/// nothing to poll, because toe already knows the frame it just wrote.
final class BorderOverlay {

    private let panel: NSPanel
    private let gradient = CAGradientLayer()
    /// The gradient's mask. A plain CALayer, not a CAShapeLayer: only CALayer draws macOS's
    /// continuous-curvature corners, and a mask masks by whatever alpha it renders — so a layer
    /// with no background and a white border is exactly the band we want.
    private let band = CALayer()
    private var config = BorderConfig()

    /// Where the border sits in the window stack. Chosen per update by
    /// `Coordinator.borderDepth(around:of:)` rather than fixed.
    enum Depth {
        /// Above every ordinary window. Where the focused window's outline belongs whenever
        /// nothing is stacked over it — which is nearly always, and is why it is the starting
        /// point rather than the exception.
        ///
        /// It cannot be the only answer, though. `.floating` is CG layer 3, and the window
        /// server composites by layer before z-order, so this level draws above every ordinary
        /// window whether or not it is really in front — which had the ring drawn straight
        /// through any dialog opened over the focused window. `WindowStack` derives its own
        /// bound from this level; the two are the same fact.
        case aboveEverything
        /// Just behind the frontmost window, above all the rest.
        ///
        /// Hyprland draws a border inside its own window's render pass, and draws the focused
        /// window last of all, so a window being dragged passes *over* the borders of the tiles
        /// it crosses rather than under them. A macOS panel cannot be slotted behind one
        /// specific window — `order(_:relativeTo:)` does not reach across processes, and the
        /// window level decides the order regardless — but the ordinary level arrives at the
        /// same place anyway: toe is a background app, so a normal-level panel lands directly
        /// beneath the frontmost application's window, which is the one in the user's hand.
        ///
        /// It does the same job for a window stacked over the focused one: at the ordinary
        /// level the ring still draws above every inactive application, so it stays visible
        /// all the way round the focused window, while the window in front covers the part of
        /// it that it genuinely overlaps.
        case behindFrontmost

        var level: NSWindow.Level { self == .aboveEverything ? .floating : .normal }
    }

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.addSublayer(gradient)
        gradient.mask = band
        band.backgroundColor = nil                  // the middle stays transparent
        band.borderColor = NSColor.white.cgColor    // mask alpha only; the colour is the gradient's
        band.cornerCurve = .continuous              // macOS's squircle, not a circular arc
        panel.contentView = view

        // Resolves the system corner radius here, on the main thread, and records it once.
        Log.info("system window corner radius: \(SystemCornerRadius.points) pt (\(SystemCornerRadius.source))")
    }

    func apply(_ newConfig: BorderConfig) {
        config = newConfig
        gradient.colors = [Self.color(newConfig.activeStart), Self.color(newConfig.activeEnd)]
        // Hyprland measures the gradient angle counter-clockwise from "left to right".
        let radians = newConfig.angle * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        gradient.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
        gradient.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
        if !newConfig.enabled { hide() }
        // The band's width and radius move together and depend on the window, so both are set
        // in show() rather than here.
    }

    /// `box` is the window's own frame in AX coordinates; the border is drawn just outside it.
    ///
    /// `depth` has no default on purpose: both call sites decide it, and a default is how a
    /// future one would silently go back to drawing over whatever is in front of it.
    func show(around box: Box, depth: Depth) {
        guard config.enabled, config.width > 0 else { hide(); return }

        let w = config.width
        // The same `outset` the depth decision measures against, so what is drawn and what is
        // tested for coverage cannot drift apart.
        let outer = BorderGeometry.outset(box, by: w)
        let rect = Coordinates.toCocoa(outer)
        guard rect.width > 0, rect.height > 0 else { hide(); return }

        let windowRadius = BorderGeometry.effectiveRadius(configured: config.radius,
                                                          system: Double(SystemCornerRadius.points),
                                                          box: box)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(rect, display: false)
        let bounds = CGRect(origin: .zero, size: rect.size)
        panel.contentView?.frame = bounds
        gradient.frame = bounds
        // CALayer.borderWidth draws inside the bounds, unlike a CAShapeLayer stroke, so the band
        // fills the whole outset with no half-line-width inset. Clearing the window's radius by
        // the band width is what lands the band's inner edge on the window's own corner.
        band.frame = bounds
        band.borderWidth = w
        band.cornerRadius = BorderGeometry.outerRadius(inner: windowRadius, width: w)
        // A mask rasterises at its own contentsScale, which defaults to 1 — without this the
        // border is soft on Retina. Re-read every time: the panel can change display.
        let scale = panel.backingScaleFactor
        if gradient.contentsScale != scale { gradient.contentsScale = scale }
        if band.contentsScale != scale { band.contentsScale = scale }
        CATransaction.commit()

        // Re-ordered on every show, not just when the depth changes: `behindFrontmost` is a
        // position in the stack rather than a fixed level, so it has to be re-taken whenever
        // the application in front of it changes.
        if panel.level != depth.level { panel.level = depth.level }
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Parses `#RRGGBB` and `#RRGGBBAA` (Hyprland's `rgba()` ordering).
    private static func color(_ hex: String) -> CGColor {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.hasPrefix("0x") { text.removeFirst(2) }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else {
            return NSColor.systemBlue.cgColor
        }
        let hasAlpha = text.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }
}
