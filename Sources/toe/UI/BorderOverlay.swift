import AppKit
import ToeCore

/// A click-through panel that outlines the focused window, reproducing Omarchy's
/// `col.active_border` gradient. Repositioned on focus and layout changes only — there is
/// nothing to poll, because toe already knows the frame it just wrote.
final class BorderOverlay {

    private let panel: NSPanel
    private let band = GradientBand()
    private var config = BorderConfig()

    /// Where the border sits in the window stack.
    enum Depth {
        /// Above every ordinary window — the focused window's own outline, which nothing
        /// should cover.
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
        /// That reasoning holds only while toe is not itself the frontmost app. The quick menu
        /// activates toe, which would break it — so the border is hidden outright for as long as
        /// that panel is open, and a drag cannot be in flight while it is.
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
        view.layer?.addSublayer(band.layer)
        panel.contentView = view

        // Resolves the system corner radius here, on the main thread, and records it once.
        Log.info("system window corner radius: \(SystemCornerRadius.points) pt (\(SystemCornerRadius.source))")
    }

    func apply(_ newConfig: BorderConfig) {
        config = newConfig
        band.apply(newConfig)
        if !newConfig.enabled { hide() }
        // The band's width and radius move together and depend on the window, so both are set
        // in show() rather than here.
    }

    /// `box` is the window's own frame in AX coordinates; the border is drawn just outside it.
    func show(around box: Box, depth: Depth = .aboveEverything) {
        guard config.enabled, config.width > 0 else { hide(); return }

        let w = config.width
        let outer = Box(x: box.x - w, y: box.y - w, w: box.w + 2 * w, h: box.h + 2 * w)
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
        // Clearing the window's radius by the band width is what lands the band's inner edge on
        // the window's own corner.
        band.layout(in: bounds,
                    width: w,
                    radius: BorderGeometry.outerRadius(inner: windowRadius, width: w),
                    scale: panel.backingScaleFactor)
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
}
