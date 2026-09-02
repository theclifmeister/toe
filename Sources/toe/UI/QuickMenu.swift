import AppKit
import ToeCore

/// A borderless panel that can take the keyboard.
///
/// `canBecomeKey` is overridden because a borderless window answers false by default, and
/// `becomesKeyOnlyIfNeeded` is turned off because `NSPanel` otherwise hands key status only to a
/// window that contains a control asking for it — and this one contains no controls at all.
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Omarchy's menu, on `SUPER`+`SPACE`.
///
/// toe is an agent with no windows and no Dock icon, and everything it can do to itself lives on
/// a key binding — which is faithful to waybar, whose strip has nothing behind it either, but
/// leaves a Mac user with no way to *find* any of it. Omarchy has exactly the surface that fills
/// that gap, and it is not a menu bar menu: it is the one walker draws for `omarchy-menu`. This
/// is that, ported — the same rows, the same filter, the same stylesheet.
///
/// **It never activates toe.** The panel is a `.nonactivatingPanel`, so the window server routes
/// keys to it while the application the user was in stays frontmost: their title bar does not
/// dim and their menu bar does not change. That is worth the override above, because activating
/// would also walk straight into `Coordinator.isEchoOfOwnRaise`, which reads
/// `NSWorkspace.frontmostApplication` to tell a real focus change from the echo of a raise toe
/// asked for — make toe frontmost and that test starts answering "echo" for everything.
final class QuickMenu {

    /// Where a chosen row goes. `Coordinator` hands these straight to `dispatch`.
    var onCommand: ((Command) -> Void)?

    private let panel: MenuPanel
    private let view = MenuView()
    private var state: MenuState?
    private var page: MenuPage = .root
    private var config = Config()
    private var usable: Box?
    private var metrics = MenuMetrics(lineHeight: 22)
    /// Guards the close path against itself: ordering the panel out resigns key, which is one of
    /// the things that closes the menu.
    private var isClosing = false
    /// Who was in front when the menu opened, so a stray activation can be put back.
    private var frontmostAtOpen: pid_t?
    private var observers: [any NSObjectProtocol] = []

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = MenuPanel(contentRect: .zero,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // walker's .box-wrapper casts none
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Above the focus border's `.floating`, so the ring stays drawn around the menu rather
        // than over it — which is what walker looks like above a Hyprland border.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = view

        view.onKeyDown = { [weak self] event in self?.handle(event) }
        view.onSelectRow = { [weak self] row in
            self?.state?.select(row: row)
            self?.render()
        }
        view.onActivateRow = { [weak self] row in
            guard let self else { return }
            state?.select(row: row)
            act(on: state?.activate() ?? .none)
        }
    }

    deinit { close() }

    // MARK: - Opening and closing

    /// The hotkey. A second press closes: `RegisterEventHotKey` intercepts ahead of the key
    /// window, so `SUPER`+`SPACE` reaches this rather than typing a space into the filter.
    func toggle(page: MenuPage, config: Config, usable: Box?) {
        if isVisible, page == self.page {
            close()
            return
        }
        self.config = config
        self.usable = usable
        open(page: page)
    }

    private func open(page: MenuPage) {
        self.page = page
        MenuFont.register()

        let font = MenuFont.text(size: config.menu.fontSize)
        // Measured rather than assumed: `MenuLayout` cannot ask a font how tall a line is, and
        // every metric below it is derived from this one.
        metrics = MenuMetrics(fontSize: config.menu.fontSize,
                              lineHeight: ceil(Double(font.ascender - font.descender + font.leading)))
        let subtitle = MenuFont.text(size: config.menu.fontSize * Self.subtitleScale)
        metrics.subtitleLineHeight =
            ceil(Double(subtitle.ascender - subtitle.descender + subtitle.leading))

        let items = page == .keybindings
            ? MenuModel.keybindings(config.bindings, superKey: config.superKey)
            : MenuModel.root(loginItem: LoginItem.state(), bindings: config.bindings)
        state = MenuState(root: items, visibleRows: 10)

        frontmostAtOpen = NSWorkspace.shared.frontmostApplication?.processIdentifier
        observe()
        layoutAndRender()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    func close() {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        panel.orderOut(nil)
        stopObserving()
        state = nil
        isClosing = false

        // Only when toe itself ended up in front. Dismissing by clicking another application is
        // the common case and their click must stand — this is here for the one where the panel
        // pulled the application forward despite `.nonactivatingPanel`, which would otherwise
        // leave the user typing into toe.
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
        switch event.keyCode {
        case 0x35:                                  // escape
            act(on: state?.pop() ?? .closed)
        case 0x24:                                  // return
            act(on: state?.activate() ?? .none)
        case 0x7D: move(1)                          // down
        case 0x7E: move(-1)                         // up
        case 0x7B:                                  // left
            act(on: state?.pop() ?? .closed)
        case 0x7C:                                  // right
            if state?.selectedItem?.leadsOn == true { act(on: state?.activate() ?? .none) }
        case 0x73: state?.moveToTop(); render()     // home
        case 0x77: state?.moveToEnd(); render()     // end
        case 0x74: move(-(state?.visibleRows ?? 1)) // page up
        case 0x79: move(state?.visibleRows ?? 1)    // page down
        case 0x33:                                  // backspace
            // walker's: eat a character, and when there is none left, leave the submenu.
            if state?.backspace() == false, state?.isAtRoot == false {
                act(on: state?.pop() ?? .none)
            } else {
                layoutAndRender()
            }
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
            else { return }
            state?.type(characters)
            layoutAndRender()
        }
    }

    private func move(_ delta: Int) {
        state?.move(by: delta)
        render()
    }

    private func act(on outcome: MenuOutcome) {
        switch outcome {
        case .pushed, .popped:
            layoutAndRender()
        case .closed:
            close()
        case .none:
            render()
        case .page(let page):
            open(page: page)
        case .toggleLoginItem:
            // Deliberately does not close: the value flips under the cursor, as omarchy-menu's
            // toggles do, so you can see what you just did.
            let setup = MenuModel.configure(loginItem: LoginItem.toggle(),
                                            bindings: config.bindings)
            // The level itself rather than the root's first row: Configure is not always the
            // first row, and on the day the toggle answers `unavailable` it is not there at all.
            if !setup.isEmpty { state?.replaceLevel(with: setup) }
            layoutAndRender()
        case .run(let command):
            // Closed first, and dispatched a turn later: an `exec` brings another application
            // forward and `quit` tears the process down, and both want the panel gone and the
            // keyboard handed back before they begin.
            close()
            DispatchQueue.main.async { [weak self] in self?.onCommand?(command) }
        }
    }

    // MARK: - Geometry

    /// The path line under a searched-for row, relative to the row's own text.
    static let subtitleScale = 0.72

    private func layoutAndRender() {
        guard var current = state else { return }
        // Rows grow a second line while the list is a search rather than one level of the tree,
        // and they grow together — a list of rows that were each as tall as their own contents
        // would be a ragged one.
        metrics.showsSubtitles = !current.query.isEmpty
        let area = usable ?? Coordinates.toAX(NSScreen.main?.visibleFrame ?? .zero)
        let wanted = page == .keybindings ? config.menu.listWidth : config.menu.width
        // Clamped, so `list_width = 800` on a laptop is a wide menu rather than one with its
        // ends off the screen.
        let width = min(wanted, area.w - MenuLayout.contentInset(metrics) * 2)

        let (size, rows) = MenuLayout.size(rows: current.visible.count, width: width,
                                           maxHeight: area.h * 0.8, metrics)
        current.setVisibleRows(rows)
        state = current

        panel.setFrame(Coordinates.toCocoa(MenuLayout.centred(size: size, on: area)), display: false)
        render()
    }

    private func render() {
        guard let state else { return }
        let menu = config.menu
        view.snapshot = MenuSnapshot(
            prompt: state.prompt,
            query: state.query,
            rows: Array(state.window),
            selectedRow: state.selection - state.scroll,
            metrics: metrics,
            valueColumn: page == .keybindings ? 0.5 : nil,
            background: Colors.rgba(menu.background, or: RGBA(r: 0.10, g: 0.11, b: 0.15, a: 1)),
            foreground: Colors.rgba(menu.foreground, or: RGBA(r: 0.66, g: 0.69, b: 0.84, a: 1)),
            accent: Colors.rgba(menu.accent, or: RGBA(r: 0.48, g: 0.64, b: 0.97, a: 1)),
            border: Colors.rgba(menu.borderColor, or: RGBA(r: 0.66, g: 0.69, b: 0.84, a: 1)),
            opacity: menu.opacity)
        // The panel is a blank canvas to VoiceOver otherwise — the same care `StatusItem` takes
        // over a title that is a row of squares.
        view.setAccessibilityLabel(accessibilityLabel(state))
    }

    private func accessibilityLabel(_ state: MenuState) -> String {
        guard let item = state.selectedItem else { return "\(state.prompt) no matches" }
        return "\(state.prompt) \(item.title), row \(state.selection + 1) of \(state.visible.count)"
    }

    // MARK: - Dismissal

    private func observe() {
        guard observers.isEmpty else { return }
        add(NSWindow.didResignKeyNotification, object: panel) { [weak self] _ in self?.close() }
        // A display coming or going moves the area the menu was centred on. Closing is honest;
        // re-centring mid-keystroke is a menu that jumps out from under the pointer.
        add(NSApplication.didChangeScreenParametersNotification, object: nil) { [weak self] _ in
            self?.close()
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
    }
}
