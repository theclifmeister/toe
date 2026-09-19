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
    var onScroll: ((BarItem.Kind?, Int) -> Void)? {
        get { view.onScroll }
        set { view.onScroll = newValue }
    }

    // MARK: The peek — `MenuBarPeek`, driven

    /// `[bar] menu_bar_peek`. Off, the pointer on the strip is not watched at all.
    var peekEnabled = true
    /// Whether the panel is out of the way for the menu bar under it. `BarWindowSet.refresh`
    /// leaves a peeking panel hidden; `onPeekChanged` is how it hears the peek is over.
    private(set) var isPeeking = false
    var onPeekChanged: (() -> Void)?
    private var peek = MenuBarPeek()
    /// The pointer sampled every 50 ms, but only while it is on the strip or the peek is on —
    /// the rest of the time nothing ticks. `NSEvent.mouseLocation` rather than a global mouse
    /// monitor: sketchybar's maintainer measured a system-wide mouse-move handler and refused
    /// to carry the cost, and a poll bounded to the time the pointer spends on the strip has
    /// no cost anywhere else. The tracking area is what starts it — a hidden panel gets no
    /// tracking events, which is why the timer, not the tracking area, carries the peek.
    private var sampler: Timer?
    /// Where the strip is, in Cocoa coordinates, kept while the panel is ordered out.
    private var stripRect: NSRect = .zero

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
        // One level *above* the menu bar — sketchybar's `topmost`. The bar covers the menu bar
        // rather than replacing it: the first cut set the system's auto-hide instead and sat
        // one level under, and every trip of the pointer to the top edge slid the menu bar
        // back in over the bar. Measured for #171: a panel at 25 draws over the menu bar
        // entirely, at 24 the menu bar's items draw over it. The menu bar keeps its strip of
        // `visibleFrame`, which is honest — the bar is on it — and keeps its menus for the
        // keyboard; `bar hide` takes the panels away, and the menu bar is what is left.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.isReleasedWhenClosed = false
        // `.fullScreenAuxiliary` so the panel may exist on a fullscreen Space at all, which is
        // what lets it be hidden there deliberately rather than by the window server; see
        // `BarWindowSet`. `.stationary` keeps Mission Control from sweeping it up as a window.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // A bar does not zoom in; it is there or it is not.
        panel.animationBehavior = .none
        panel.contentView = view
        view.onPointerEntered = { [weak self] in self?.startSampling() }
    }

    /// Puts the panel across the top of `screen` at `height`, and draws `snapshot` into it with
    /// the centre section centred on `centre` — see `BarWindowSet.centre(on:)`.
    func show(on screen: NSScreen, height: Double, centre: Double?, snapshot: BarSnapshot) {
        let frame = screen.frame
        let rect = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        if panel.frame != rect { panel.setFrame(rect, display: false) }
        stripRect = rect
        panel.backgroundColor = NSColor(snapshot.background)
        view.centre = centre
        view.snapshot = snapshot
        panel.orderFrontRegardless()
    }

    /// Takes the panel off screen for the set's reasons — `bar hide`, a fullscreen window, the
    /// bar switched off — which end any peek: the bar is not coming back on its own.
    func hide() {
        stopSampling()
        panel.orderOut(nil)
    }

    private func startSampling() {
        guard peekEnabled, sampler == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.samplePointer() }
        // `.common` so the sampling survives a menu being tracked: a dropped-down menu runs
        // the run loop in event-tracking mode, and a timer on the default mode alone would
        // stop for exactly the time the peek exists for.
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    private func stopSampling() {
        sampler?.invalidate()
        sampler = nil
        peek.reset()
        isPeeking = false
    }

    private func samplePointer() {
        let location = NSEvent.mouseLocation
        let onStrip = stripRect.minX <= location.x && location.x < stripRect.maxX
            && stripRect.minY <= location.y && location.y <= stripRect.maxY
        let pointer = MenuBarPeek.pointer(y: onStrip ? Double(stripRect.maxY - location.y) : nil,
                                          height: Double(stripRect.height))
        // The window list is asked only when the answer can matter — the pointer has left the
        // strip mid-peek — so a pointer resting on a widget costs no window-server round trip.
        let menuOpen = isPeeking && pointer == .away && Self.isMenuOpen()
        guard peek.sample(pointer, menuOpen: menuOpen, at: ProcessInfo.processInfo.systemUptime) else {
            // Nothing pending and the pointer gone: the tracking area will start this again.
            if !peek.isPeeking, pointer == .away { stopSampling() }
            return
        }
        isPeeking = peek.isPeeking
        if isPeeking {
            panel.orderOut(nil)
        } else {
            stopSampling()
        }
        onPeekChanged?()
    }

    /// Whether an application has a menu dropped down. Measured for this: a menu bar's menu is
    /// an on-screen window at `kCGPopUpMenuWindowLevel`, 101, owned by the application, sitting
    /// just under the menu bar's strip — the window list is the one place outside that
    /// application it can be seen from. Context menus are at the same level and keep the peek
    /// too, which is harmless: they close, and the linger runs from there.
    private static func isMenuOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
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
    /// The wheel over a slot, in whole notches: positive is up, which on a volume is louder.
    var onScroll: ((BarItem.Kind?, Int) -> Void)?
    /// The pointer arriving on the strip — what starts `BarPanel`'s sampling for the peek.
    /// Only the arrival: the panel finds out about leaving by sampling, since a panel that
    /// has ordered itself out for the peek is not told anything by a tracking area.
    var onPointerEntered: (() -> Void)?
    /// Upstream's `wheelSteps` accumulator: a trackpad emits many small deltas for one notch of
    /// a wheel, so they are summed and a step is reported per notch's worth, with the remainder
    /// carried and dropped when the direction reverses.
    private var scrollAccumulator: Double = 0

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
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

    override func scrollWheel(with event: NSEvent) {
        // A wheel notch is a whole line; a trackpad reports pixels and much smaller numbers,
        // and `hasPreciseScrollingDeltas` says which. Ten points of trackpad is one notch.
        let delta = event.hasPreciseScrollingDeltas ? Double(event.scrollingDeltaY) / 10
                                                    : Double(event.scrollingDeltaY)
        if scrollAccumulator * delta < 0 { scrollAccumulator = 0 }
        scrollAccumulator += delta
        let steps = scrollAccumulator < 0 ? Int(scrollAccumulator.rounded(.up))
                                          : Int(scrollAccumulator.rounded(.down))
        scrollAccumulator -= Double(steps)
        guard steps != 0 else { return }
        onScroll?(kind(under: event), steps)
    }

    private func kind(under event: NSEvent) -> BarItem.Kind? {
        let point = convert(event.locationInWindow, from: nil)
        return BarLayout.hit(x: Double(point.x), in: placed)?.item.kind
    }
}
