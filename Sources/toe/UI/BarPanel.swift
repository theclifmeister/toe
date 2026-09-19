import AppKit
import ToeCore

/// One display's strip of Omarchy's bar: a panel across the top of the screen, and the view
/// that draws the items into it.
///
/// A panel per `NSScreen` rather than one spanning them all, because the bar is per display in
/// Omarchy too — each has its own clock in its own centre — and because a window that spans two
/// displays of different scale is a window the window server renders at the worse of the two.
/// `BarWindowSet` keeps the set in step with the displays.
///
/// Drawn with `draw(_:)` the way `MenuView` is: one flipped view, attributed strings, the same
/// face for text and glyphs. Not a layer per item — the bar redraws on a focus change and once
/// a minute for the clock, and a dozen `CATextLayer`s to express what one loop draws directly
/// would be the object graph `MenuView` declined to build.
final class BarPanel {

    let panel: NSPanel
    private let view = BarView()
    /// The display this strip belongs to, so a click can be reported against it and the set
    /// can tell which panels have lost their screen.
    let displayID: CGDirectDisplayID

    /// A click, by what was under it and which button; `nil` over bare bar.
    var onClick: ((BarItem.Kind?, BarView.Button) -> Void)? {
        get { view.onClick }
        set { view.onClick = newValue }
    }

    init(screen: NSScreen) {
        displayID = screen.displayID
        panel = TopStripPanel(contentRect: .zero,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.hasShadow = false
        // Clicks land: the whole point of a menu widget is pressing it. `.nonactivatingPanel`
        // is what keeps a click from bringing toe forward and taking the focus off whatever the
        // user was in, which for a background agent with no windows would be a focus into
        // nothing.
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        // One level under the menu bar, where `SlideOverlay` sits: above every ordinary and
        // floating window and the Dock, below the menu bar itself — so when the hidden menu bar
        // slides in on hover it comes in *over* the bar, and the application's menus are
        // reachable through it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        panel.isReleasedWhenClosed = false
        // `.fullScreenAuxiliary` so the panel may exist on a fullscreen Space at all, which is
        // what lets it be hidden there deliberately rather than by the window server; see
        // `BarWindowSet`. `.stationary` keeps Mission Control from sweeping it up as a window.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // A bar does not zoom in; it is there or it is not.
        panel.animationBehavior = .none
        panel.contentView = view
    }

    /// Puts the panel across the top of `screen` at `height`, and draws `snapshot` into it with
    /// the centre section centred on `centre` — see `BarWindowSet.centre(on:)`.
    func show(on screen: NSScreen, height: Double, centre: Double?, snapshot: BarSnapshot) {
        let frame = screen.frame
        let rect = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        if panel.frame != rect { panel.setFrame(rect, display: false) }
        panel.backgroundColor = NSColor(snapshot.background)
        view.centre = centre
        view.snapshot = snapshot
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// A panel allowed into the top strip of a notched display.
///
/// AppKit keeps every window out of a screen's top safe area — the strip beside the camera
/// housing — by way of `constrainFrameRect(_:to:)`, which slides a frame down until it clears
/// `safeAreaInsets.top`. That is right for a document window and wrong for the bar, whose whole
/// job is that strip: measured for #171, a plain `NSPanel` asked for the top 26 points of the
/// built-in display was put at 32 to 58 instead, over the tiles. The constraint is AppKit's, not
/// the window server's — the menu bar itself lives there — so overriding it is enough.
private final class TopStripPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The bar, drawn.
final class BarView: NSView {

    enum Button { case left, right, middle }

    var snapshot: BarSnapshot? {
        didSet { needsDisplay = true }
    }
    /// Where the anchor is centred, in the view's coordinates; nil is the middle.
    var centre: Double? {
        didSet { if centre != oldValue { needsDisplay = true } }
    }
    var onClick: ((BarItem.Kind?, Button) -> Void)?

    /// What the last draw put where, for the click that follows it. Laid out in `draw` rather
    /// than when the snapshot arrives because the width is the view's, and the view's width is
    /// the display's — the same items lay out differently on every screen.
    private var placed: [BarLayout.Placed] = []
    /// Set on a press, cleared on the release: the outer optional is whether a button is down,
    /// the inner what it went down on, which may be nothing.
    private var mouseDownKind: BarItem.Kind??

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // One tooltip region over the whole strip, answered by point: the slots move as the
        // clock's label changes width, so a rect per item would be stale by the next minute.
        addToolTip(.zero, owner: self, userData: nil)
    }

    required init?(coder: NSCoder) { fatalError("BarView is built in code") }

    override func layout() {
        super.layout()
        removeAllToolTips()
        addToolTip(bounds, owner: self, userData: nil)
    }

    /// `NSViewToolTipOwner`: the tooltip for whatever slot the pointer rests on.
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
                    userData: UnsafeMutableRawPointer?) -> String {
        BarLayout.hit(x: Double(point.x), in: placed)?.item.tooltip ?? ""
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let s = snapshot else { return }
        let m = s.metrics
        let height = Double(bounds.height)

        NSColor(s.background).setFill()
        bounds.fill()

        placed = BarLayout.place(s.items, width: Double(bounds.width), metrics: m, centre: centre) { text, size in
            Double(NSAttributedString(string: text, attributes: [.font: MenuFont.text(size: size)])
                .size().width)
        }
        for slot in placed where !slot.item.isHidden {
            let item = slot.item
            let colour = (item.active ? s.active : s.foreground).withAlpha(item.opacity)

            if item.kind == .menu {
                // The mark, centred in its slot the way a label would be. `flipped`, since the
                // view is.
                let mark = NSRect(x: ToeMark.snap(slot.midX - s.markWidth / 2),
                                  y: ToeMark.snap((height - s.markHeight) / 2),
                                  width: s.markWidth, height: s.markHeight)
                ToeMark.draw(in: mark, colour: NSColor(colour), flipped: true)
                continue
            }

            // `Text { anchors.centerIn: parent }`: the label's own box, centred in the slot both
            // ways. Vertical centring uses the line box rather than the glyph's ink, which is
            // what Qt's `AlignVCenter` does too — so a digit and a glyph beside it share a
            // baseline rather than each being centred on its own shape.
            let font = MenuFont.text(size: m.pointSize(item.font))
            let string = NSAttributedString(string: item.text,
                                            attributes: [.font: font, .foregroundColor: NSColor(colour)])
            let size = string.size()
            string.draw(at: NSPoint(x: slot.midX - Double(size.width) / 2,
                                    y: (height - Double(size.height)) / 2))
        }
    }

    // MARK: - Events

    override func mouseDown(with event: NSEvent) { mouseDownKind = .some(kind(under: event)) }
    override func rightMouseDown(with event: NSEvent) { mouseDownKind = .some(kind(under: event)) }
    override func otherMouseDown(with event: NSEvent) { mouseDownKind = .some(kind(under: event)) }

    override func mouseUp(with event: NSEvent) { release(event, .left) }
    override func rightMouseUp(with event: NSEvent) { release(event, .right) }
    override func otherMouseUp(with event: NSEvent) { release(event, .middle) }

    /// Only when the button is let go over the slot it went down on, the way every other
    /// button behaves — a press that wanders off a widget is a change of mind.
    private func release(_ event: NSEvent, _ button: Button) {
        defer { mouseDownKind = nil }
        let now = kind(under: event)
        guard let down = mouseDownKind, down == now else { return }
        onClick?(now, button)
    }

    private func kind(under event: NSEvent) -> BarItem.Kind? {
        let point = convert(event.locationInWindow, from: nil)
        return BarLayout.hit(x: Double(point.x), in: placed)?.item.kind
    }
}
