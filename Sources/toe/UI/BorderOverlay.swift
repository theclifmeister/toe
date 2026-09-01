import AppKit
import ToeCore

/// A click-through panel that outlines the focused window, reproducing Omarchy's
/// `col.active_border` gradient. Repositioned on focus and layout changes only — there is
/// nothing to poll, because toe already knows the frame it just wrote.
final class BorderOverlay {

    private let panel: NSPanel
    private let gradient = CAGradientLayer()
    private let shape = CAShapeLayer()
    private var config = BorderConfig()

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
        gradient.mask = shape
        shape.fillColor = nil
        shape.strokeColor = NSColor.white.cgColor
        panel.contentView = view
    }

    func apply(_ newConfig: BorderConfig) {
        config = newConfig
        gradient.colors = [Self.color(newConfig.activeStart), Self.color(newConfig.activeEnd)]
        // Hyprland measures the gradient angle counter-clockwise from "left to right".
        let radians = newConfig.angle * .pi / 180
        let dx = cos(radians) / 2, dy = sin(radians) / 2
        gradient.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
        gradient.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
        shape.lineWidth = newConfig.width
        if !newConfig.enabled { hide() }
    }

    /// `box` is the window's own frame in AX coordinates; the border is drawn just outside it.
    func show(around box: Box) {
        guard config.enabled, config.width > 0 else { hide(); return }

        let w = config.width
        let outer = Box(x: box.x - w, y: box.y - w, w: box.w + 2 * w, h: box.h + 2 * w)
        let rect = Coordinates.toCocoa(outer)
        guard rect.width > 0, rect.height > 0 else { hide(); return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(rect, display: false)
        let bounds = CGRect(origin: .zero, size: rect.size)
        panel.contentView?.frame = bounds
        gradient.frame = bounds
        shape.frame = bounds
        // Stroke straddles the path, so inset by half the line width to keep it inside.
        shape.path = CGPath(roundedRect: bounds.insetBy(dx: w / 2, dy: w / 2),
                            cornerWidth: config.radius, cornerHeight: config.radius,
                            transform: nil)
        CATransaction.commit()

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
