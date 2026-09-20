import AppKit
import ToeCore

/// The quick menu's colours and the bar's type size, which is what a panel draws in.
struct PanelStyle: Equatable {
    var metrics: PanelMetrics
    var background: RGBA
    var foreground: RGBA
    var accent: RGBA
    var border: RGBA
    var opacity: Double
}

/// Everything the view needs for one frame — a value, for the reason `MenuSnapshot` is one.
struct PanelSnapshot: Equatable {
    var rows: [PanelRow]
    var frames: [Box]
    var selection: Int?
    /// How far the content is scrolled up, for a card cut to the screen.
    var offset: Double
    var style: PanelStyle
    /// How far through the second since the traffic graph's newest sample the frame is, 0…1
    /// — the view's interpolation, see `PanelLayout.graphX`. 1 when there is no graph or the
    /// second is up, which is the still picture.
    var glide: Double = 1
}

/// Where a panel hangs: the widget's slot on its display, and the bar it hangs from.
struct PanelAnchor: Equatable {
    /// The slot's centre in the display's own coordinates.
    var slotMidX: Double
    var barHeight: Double
    /// The display's frame in Accessibility coordinates.
    var display: Box
    var displayID: CGDirectDisplayID
}

/// One popover for every widget — Omarchy's `KeyboardPanel`, on `MenuPanel`'s footing.
///
/// One window rather than one per panel, because only one is ever open (`Bar.requestPopout`
/// upstream closes the previous one) and the six panels differ only in their rows. Opening a
/// second kind replaces the rows and moves the card under the other widget; the window is
/// never closed and reopened for a switch, which is upstream's `popoutSwitching` — a card that
/// blinked out and in on every Tab would read as two panels rather than one moving.
///
/// It never activates toe, for the reason `QuickMenu` does not — see `Coordinator.isEchoOfOwnRaise`
/// — and takes the keyboard the way the menu does: `.nonactivatingPanel`, key, first
/// responder on the view. Closing is Escape, a click outside, or losing key to another
/// application; a click on the bar is not "outside" but the bar's to answer — `barClicked`
/// closes this and opens whatever was pressed — so the click monitor lets those through.
final class BarPanelWindow {

    /// A row pressed. The Coordinator hands it to the provider that can do it.
    var onAction: ((PanelAction) -> Void)?
    /// A slider moved — ←/→, the wheel, a drag — to this value.
    var onSlide: ((PanelSlider, Double) -> Void)?
    /// Tab and Shift-Tab: the panel one widget over, upstream's `switchPanel`.
    var onSwitch: ((Int) -> Void)?
    /// The panel has gone, by whichever door — Escape, a click elsewhere, losing key, a screen
    /// change, the Coordinator's own `close`. The one place to stop what ran only for it.
    var onClose: (() -> Void)?

    private let panel: MenuPanel
    private let view = PanelView()
    private var state: PanelState?
    private var style: PanelStyle?
    private var anchor: PanelAnchor?
    private var frames: [Box] = []
    private var contentHeight: Double = 0
    private var offset: Double = 0
    private(set) var kind: PanelKind?
    private var observers: [any NSObjectProtocol] = []
    private var clickMonitor: Any?
    private var isClosing = false
    private var frontmostAtOpen: pid_t?

    /// The traffic graph's glide (#189): when the graph row's window changes under `update`,
    /// the newest sample has just landed and the trace has a second to slide one width left.
    /// `glideTimer` redraws at display rate until it has, then stops — it is alive only while
    /// a graph row is on screen *and* moving, so an open panel with its minute already still
    /// costs nothing, and a closed one nothing at all. Timer rather than `CVDisplayLink`: the
    /// panel is one small card, 60 Hz is what the eye asked for, and a display link wants a
    /// thread the rest of this window does not have.
    private var glideTimer: Timer?
    private var glideStarted: TimeInterval?
    private var lastGraph: NetworkTraffic.Window?
    private static let glideFrame: TimeInterval = 1.0 / 60

    var isVisible: Bool { panel.isVisible }
    /// The display the open panel is on, so a fullscreen window there — and only there —
    /// can close it.
    var displayID: CGDirectDisplayID? { anchor?.displayID }

    init() {
        panel = MenuPanel(contentRect: .zero,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Above the bar, which is one over the menu bar; `.popUpMenu` is where the quick menu
        // sits and is above both.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = view
        // Every keystroke and click comes back here; the view draws and hit-tests, nothing more.
        view.onKeyDown = { [weak self] event in self?.handle(event) }
        view.onHover = { [weak self] row in self?.hover(row) }
        view.onPress = { [weak self] row, button, point in self?.press(row, button, at: point) }
        view.onDrag = { [weak self] row, point in self?.drag(row, to: point) }
        view.onRelease = { [weak self] row in self?.release(row) }
        view.onScroll = { [weak self] row, steps, delta in self?.scroll(row, steps: steps, delta: delta) }
    }

    deinit { close() }

    // MARK: - Opening and closing

    /// Shows `rows` as `kind`'s panel under `anchor`, or moves an open panel there.
    func open(_ kind: PanelKind, rows: [PanelRow], style: PanelStyle, anchor: PanelAnchor) {
        MenuFont.register()
        let switching = isVisible
        self.kind = kind
        self.style = style
        self.anchor = anchor
        // A switch keeps nothing of the old panel's cursor: it is a different list.
        state = PanelState(rows: rows)
        offset = 0
        // Nor of the old panel's graph: the network panel's first frame is a still one.
        stopGlide()
        lastGraph = graphWindow(in: rows)
        if !switching {
            frontmostAtOpen = NSWorkspace.shared.frontmostApplication?.processIdentifier
            observe()
        }
        layoutAndRender()
        if !switching {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
        }
    }

    /// New rows from a provider while the panel is up: the cursor stays on its row — see
    /// `PanelState.replace` — and the card grows or shrinks with the list.
    func update(rows: [PanelRow], style: PanelStyle) {
        guard isVisible, state != nil else { return }
        self.style = style
        state?.replace(rows: rows)
        // A new sample in the graph row starts a glide; the same window again — the provider
        // reporting something else, the RSSI say — leaves whatever glide is running alone.
        let graph = graphWindow(in: rows)
        if let graph, graph != lastGraph, lastGraph != nil { startGlide() }
        if graph == nil { stopGlide() }
        lastGraph = graph
        layoutAndRender()
    }

    func close() {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        panel.orderOut(nil)
        stopObserving()
        stopGlide()
        lastGraph = nil
        state = nil
        kind = nil
        isClosing = false
        onClose?()
        // The same care `QuickMenu.close` takes: if toe somehow came forward, put back who was.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier,
           let pid = frontmostAtOpen,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        frontmostAtOpen = nil
    }

    // MARK: - Keys

    private func handle(_ event: NSEvent) {
        guard state != nil else { return }
        let chars = event.charactersIgnoringModifiers ?? ""
        switch event.keyCode {
        case 0x35:                                  // escape
            close()
        case 0x24, 0x4C, 0x31:                      // return, enter, space
            act(state?.activate() ?? .none)
        case 0x7D: move(1)                          // down
        case 0x7E: move(-1)                         // up
        case 0x7B: sideways(-1)                     // left
        case 0x7C: sideways(1)                      // right
        case 0x73: state?.moveToTop(); render()     // home
        case 0x77: state?.moveToEnd(); render()     // end
        case 0x30:                                  // tab
            onSwitch?(event.modifierFlags.contains(.shift) ? -1 : 1)
        default:
            // `PanelKeyCatcher`'s vi keys. A panel has no search to type into, so the letters
            // are free — the quick menu's are not, which is why it has none.
            switch chars {
            case "j": move(1)
            case "k": move(-1)
            case "h": sideways(-1)
            case "l": sideways(1)
            // The calendar's own keys, `onTextKey` in `panels/clock/Panel.qml`.
            case "[" where kind == .clock: act(.perform(.stepMonth(-1)))
            case "]" where kind == .clock: act(.perform(.stepMonth(1)))
            case "{" where kind == .clock: act(.perform(.stepMonth(-12)))
            case "}" where kind == .clock: act(.perform(.stepMonth(12)))
            case "t", "T": if kind == .clock { act(.perform(.today)) }
            case "w", "W": if kind == .clock { act(.perform(.toggleWeekStart)) }
            default: break
            }
        }
    }

    private func move(_ delta: Int) {
        state?.move(by: delta)
        render()
    }

    /// ←/→: a slider under the cursor moves; on the calendar the month steps, wherever the
    /// cursor is, since that is what the arrows mean on a calendar; anywhere else nothing.
    private func sideways(_ delta: Int) {
        if state?.selectedRow?.slider != nil {
            act(state?.adjust(by: delta) ?? .none)
        } else if kind == .clock {
            act(.perform(.stepMonth(delta)))
        }
    }

    private func act(_ outcome: PanelOutcome) {
        switch outcome {
        case .none:
            render()
        case .perform(let action):
            // The settings door is the one row that leaves: System Settings is about to come
            // forward, and the card wants to be gone before it does. Everything else — a
            // device picked, a switch thrown — shows its result under the cursor, as the
            // menu's toggles do.
            switch action {
            case .openSettings, .openCalendar: close()
            default: break
            }
            onAction?(action)
            render()
        case .slide(let slider, let value):
            onSlide?(slider, value)
            render()
        }
    }

    // MARK: - Mouse

    private func hover(_ row: Int?) {
        guard let row, let state, state.selection != row, state.rows[row].isSelectable else { return }
        self.state?.select(row: row)
        render()
    }

    /// Set on a press over a slider and cleared on release: the drag that follows moves it.
    private var draggingSlider: Int?
    private var pressedRow: Int?

    private func press(_ row: Int?, _ button: PanelView.Button, at point: Point) {
        guard let row, let state, row < state.rows.count else { return }
        let target = state.rows[row]
        if target.slider != nil {
            switch button {
            case .left:
                // `PanelSlider.onPressed`: the value jumps to the pointer and follows it.
                self.state?.select(row: row)
                draggingSlider = row
                drag(row, to: point)
            case .right:
                // `onRightClicked`: a secondary press on the whole track mutes.
                self.state?.select(row: row)
                act(self.state?.activate() ?? .none)
            }
            return
        }
        // The calendar's two controls sit on rows the cursor does not land on: the `W`
        // heading toggles the week start, and the month line's ends step it.
        if case .calendar = target.kind, button == .left, let style,
           PanelLayout.calendarHitsWeekStart(at: point, inRow: frames[row], style.metrics) {
            act(.perform(.toggleWeekStart))
            return
        }
        if case .monthNav = target.kind, button == .left, let style {
            let step = PanelLayout.monthNavStep(x: point.x, inRow: frames[row], style.metrics)
            if step != 0 {
                act(.perform(.stepMonth(step)))
                return
            }
        }
        guard target.isSelectable, button == .left else { return }
        self.state?.select(row: row)
        pressedRow = row
        render()
    }

    private func drag(_ row: Int?, to point: Point) {
        guard let dragging = draggingSlider, frames.indices.contains(dragging), let style else { return }
        let value = PanelLayout.sliderValue(x: point.x, inRow: frames[dragging], style.metrics)
        act(state?.set(row: dragging, to: value) ?? .none)
    }

    private func release(_ row: Int?) {
        defer { draggingSlider = nil; pressedRow = nil }
        guard draggingSlider == nil, let row, row == pressedRow else { return }
        // Let go over the row it went down on, the way every button behaves.
        act(state?.activate() ?? .none)
    }

    /// The wheel: over a slider it is the slider's, as it is over the bar's audio widget;
    /// anywhere else it scrolls a card that is taller than the screen let it be.
    private func scroll(_ row: Int?, steps: Int, delta: Double) {
        if let row, state?.rows[row].slider != nil, steps != 0 {
            act(state?.adjust(row: row, by: steps) ?? .none)
            return
        }
        guard let style else { return }
        offset = PanelLayout.scroll(offset: offset - delta, cursor: nil,
                                    viewport: Double(panel.frame.height), content: contentHeight,
                                    style.metrics)
        render()
    }

    // MARK: - Geometry

    private func layoutAndRender() {
        guard let state, let style, let anchor, let kind else { return }
        let m = style.metrics
        let width = kind == .clock ? m.calendarWidth : m.width
        let (frames, height) = PanelLayout.frames(state.rows, width: width, m)
        self.frames = frames
        contentHeight = height
        let frame = PanelLayout.anchor(size: Point(x: width, y: height), underSlotAt: anchor.slotMidX,
                                       barHeight: anchor.barHeight, display: anchor.display, m)
        panel.setFrame(Coordinates.toCocoa(frame), display: false)
        render()
    }

    private func render() {
        guard let state, let style else { return }
        let cursor = state.selection.flatMap { frames.indices.contains($0) ? frames[$0] : nil }
        offset = PanelLayout.scroll(offset: offset, cursor: cursor, viewport: Double(panel.frame.height),
                                    content: contentHeight, style.metrics)
        view.snapshot = PanelSnapshot(rows: state.rows, frames: frames, selection: state.selection,
                                      offset: offset, style: style, glide: glide)
        view.setAccessibilityLabel(accessibilityLabel(state))
    }

    // MARK: - The graph's glide

    private func graphWindow(in rows: [PanelRow]) -> NetworkTraffic.Window? {
        for row in rows {
            if case .graph(let window) = row.kind { return window }
        }
        return nil
    }

    /// 0…1 through the second since the newest sample; 1 with no glide running.
    private var glide: Double {
        guard let glideStarted else { return 1 }
        return max(0, min(1, (ProcessInfo.processInfo.systemUptime - glideStarted) / 1))
    }

    private func startGlide() {
        glideStarted = ProcessInfo.processInfo.systemUptime
        guard glideTimer == nil else { return }
        let timer = Timer(timeInterval: Self.glideFrame, repeats: true) { [weak self] _ in
            guard let self else { return }
            // The second is up: this frame is the still picture, and the next sample's
            // `update` starts the timer again.
            if glide >= 1 { stopGlide() }
            render()
        }
        // `.common`, so the trace keeps moving while a menu is being tracked, as the clock ticks.
        RunLoop.main.add(timer, forMode: .common)
        glideTimer = timer
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        glideStarted = nil
    }

    private func accessibilityLabel(_ state: PanelState) -> String {
        let name = kind.map { "\($0)" } ?? "panel"
        guard let row = state.selectedRow else { return "\(name) panel" }
        switch row.kind {
        case .hero(_, let title, let status, _): return "\(name) panel, \(title), \(status)"
        case .slider(_, let value, _): return "\(name) panel, volume \(Int((value * 100).rounded()))%"
        case .pick(_, let label, _, _), .action(let label): return "\(name) panel, \(label)"
        default: return "\(name) panel"
        }
    }

    // MARK: - Dismissal

    private func observe() {
        guard observers.isEmpty else { return }
        add(NSWindow.didResignKeyNotification, object: panel) { [weak self] _ in self?.close() }
        // A display coming or going moves the bar the card hangs from; closing is honest.
        add(NSApplication.didChangeScreenParametersNotification, object: nil) { [weak self] _ in
            self?.close()
        }
        // A click anywhere in toe's own windows that is not this card and not the bar. Another
        // application's window takes key from the panel and `didResignKey` closes it; a click
        // on the bar is answered by `Coordinator.barClicked`, which closes this itself and
        // opens what was pressed — closing here first would turn a press on the open panel's
        // own widget into close-then-reopen.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, isVisible, event.window !== panel, !(event.window is TopStripPanel) else { return event }
            close()
            return event
        }
    }

    private func add(_ name: Notification.Name, object: Any?,
                     _ handler: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(
            forName: name, object: object, queue: .main, using: handler))
    }

    private func stopObserving() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}
