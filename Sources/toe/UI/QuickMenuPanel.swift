import AppKit
import ToeCore

/// The quick menu's window.
///
/// `canBecomeKey` is the load-bearing line in this file. `NSWindow` returns false for it on a
/// `.borderless` window by default, and without the override the panel appears, `makeKeyAndOrderFront`
/// silently does nothing, and every keystroke lands in whatever the user was editing. It is the
/// worst thing that can go wrong here and the cheapest to prevent.
final class QuickMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    /// Nothing about a transient menu wants to be the main window.
    override var canBecomeMain: Bool { false }
}

/// A borderless panel in walker's proportions: a rounded, blurred rectangle with the focus
/// border's own gradient around its edge.
final class QuickMenuChrome {

    let panel: QuickMenuPanel
    private let effect = NSVisualEffectView()
    private let band = GradientBand()
    private var border = BorderConfig()

    init(contentView: NSView) {
        panel = QuickMenuPanel(contentRect: .zero,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true                  // unlike BorderOverlay: a menu casts a shadow
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false          // closing is explicit, so close logic always runs
        panel.animationBehavior = .none           // no appear animation on a surface this brief
        panel.ignoresMouseEvents = false
        // Above BorderOverlay's `.floating`. The focus border is hidden while this is up anyway,
        // but nothing else should be able to cover the menu either.
        panel.level = .popUpMenu
        // The same set BorderOverlay uses, and for the same reason: it is what stops an accessory
        // app's panel from kicking the user out of another app's fullscreen space.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = QuickMenuGeometry.cornerRadius
        effect.layer?.cornerCurve = .continuous    // macOS's squircle, as BorderOverlay's band uses
        effect.layer?.masksToBounds = true
        effect.addSubview(contentView)
        effect.layer?.addSublayer(band.layer)

        panel.contentView = effect
    }

    /// The panel's accent is the `[border]` gradient, so recolouring the focus border recolours the
    /// menu — and `Style → Theme` restyles both at once, which is the point.
    func apply(_ config: BorderConfig) {
        border = config
        band.apply(config)
    }

    func setFrame(_ ax: Box, contentView: NSView) {
        let rect = Coordinates.toCocoa(ax)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(rect, display: false)
        let bounds = CGRect(origin: .zero, size: rect.size)
        effect.frame = bounds
        contentView.frame = bounds
        band.layout(in: bounds,
                    width: max(1, border.width),
                    radius: QuickMenuGeometry.cornerRadius,
                    scale: panel.backingScaleFactor)
        CATransaction.commit()
    }

    var accent: NSColor {
        NSColor(cgColor: GradientBand.cgColor(border.activeStart)) ?? .controlAccentColor
    }
}
