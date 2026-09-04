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
    /// A Setup switch: flips the setting and answers the value now in effect, which is what the
    /// level is rebuilt with. The Coordinator owns the config file.
    var onToggleSetting: ((ConfigSwitch) -> Bool)?

    /// What the bundle was stamped with, for the `About` row. nil for a binary run straight out
    /// of `.build`, which has no Info.plist to have been stamped — and the row is then left out
    /// rather than reporting a version toe does not know.
    private static let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    private let panel: MenuPanel
    private let view = MenuView()
    private var state: MenuState?
    /// Which door the menu was opened by — the page, and the level within it. Held because the
    /// hotkey toggles: pressing `SUPER`+`CTRL`+`SPACE` twice closes the background level, while
    /// pressing it with the *root* menu up switches to that level rather than closing, which is
    /// what `omarchy-menu toggle <route>` does.
    private var route: MenuRoute = .root
    private var config = Config()
    /// Handed in at every open rather than held, for the same reason `LoginItem.state()` is read
    /// there: the menu is a function of what is true when you look at it, and a theme folder that
    /// appeared a second ago should be in the list.
    private var style = StyleMenu()
    /// launchd's answer, read once when the menu opened.
    ///
    /// Held rather than re-read by `update(config:style:)`, because that runs six times a second
    /// for as long as a download lasts and `LoginItem.state()` is not free: `SMAppService.status`
    /// is an XPC round trip to launchd, and the checks before it touch `Bundle.main` and the
    /// filesystem. Nothing can change it while the menu is up except the toggle itself, which
    /// rebuilds its own level with the fresh answer and does not come through here.
    private var loginItem: LoginItemState = .off
    private var usable: Box?
    private var metrics = MenuMetrics(lineHeight: 22)
    /// Guards the close path against itself: ordering the panel out resigns key, which is one of
    /// the things that closes the menu.
    private var isClosing = false
    /// Who was in front when the menu opened, so a stray activation can be put back.
    private var frontmostAtOpen: pid_t?
    private var observers: [any NSObjectProtocol] = []
    /// The display layout the menu was opened on — one frame per screen, in order.
    ///
    /// `didChangeScreenParameters` says rather less than its name suggests: auto-hiding the Dock
    /// is a screen-parameters change too, because `visibleFrame` moves, and so the menu's own
    /// Auto-hide Dock row closed the menu on the row you had just pressed while every other
    /// switch left it up. A display coming, going or changing resolution moves a `frame`, and
    /// that is the thing the menu cannot stay open across, so that is what is compared.
    private var screenLayout: [CGRect] = []

    private static var currentScreenLayout: [CGRect] { NSScreen.screens.map(\.frame) }

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
    func toggle(route: MenuRoute, config: Config, usable: Box?, style: StyleMenu = StyleMenu()) {
        if isVisible, route == self.route {
            close()
            return
        }
        self.config = config
        self.usable = usable
        self.style = style
        open(route: route)
    }

    private func open(route: MenuRoute) {
        self.route = route
        MenuFont.register()

        measure()

        loginItem = LoginItem.state()
        let items = route.page == .keybindings
            ? MenuModel.keybindings(config.bindings, superKey: config.superKey)
            : MenuModel.root(loginItem: loginItem, config: config, style: style,
                             version: QuickMenu.version)
        state = MenuState(root: items, visibleRows: 10, path: route.path)

        frontmostAtOpen = NSWorkspace.shared.frontmostApplication?.processIdentifier
        screenLayout = Self.currentScreenLayout
        observe()
        layoutAndRender()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    /// Line heights, measured from the font the config asks for.
    ///
    /// Measured rather than assumed: `MenuLayout` cannot ask a font how tall a line is, and every
    /// metric below it is derived from this one. Its own function rather than part of `open`
    /// because `update` needs it too — a config arriving while the menu is up can have changed
    /// `font_size`, and every row height and the panel's own height come from here.
    private func measure() {
        let font = MenuFont.text(size: config.menu.fontSize)
        metrics = MenuMetrics(fontSize: config.menu.fontSize,
                              lineHeight: ceil(Double(font.ascender - font.descender + font.leading)))
        let subtitle = MenuFont.text(size: config.menu.fontSize * Self.subtitleScale)
        metrics.subtitleLineHeight =
            ceil(Double(subtitle.ascender - subtitle.descender + subtitle.leading))
    }

    /// New theme state, into a menu that is already open.
    ///
    /// The catalogue arriving and a download getting a picture further both change what the rows
    /// in front of you say, and until now neither reached them: `style` was handed in at open and
    /// held, so the list was whatever was true when you pressed the key. That was survivable
    /// while a download had the menu bar to talk through and is not now that the row is the only
    /// surface it has.
    ///
    /// The config comes with it, and that is not incidental. Finishing a download *applies* the
    /// theme, which is to say it rewrites `[menu]` — so a panel still drawing from the config it
    /// was opened with would sit there in the old theme's colours while its own rows announced
    /// the new one as `current`. The picker has to restyle itself, because it is the one surface
    /// on screen at the moment a theme changes.
    ///
    /// Only the root page is rebuilt: the keybindings page is a different tree with no theme rows
    /// in it, and rebuilding it from `MenuModel.root` would replace the page under the user. It
    /// still gets the new colours, which is why the re-render is outside that branch.
    func update(config: Config, style: StyleMenu) {
        // Row heights only change when the font does, and this runs six times a second for as
        // long as a download lasts.
        let fontChanged = config.menu.fontSize != self.config.menu.fontSize
        self.config = config
        self.style = style
        guard panel.isVisible, state != nil else { return }
        if fontChanged { measure() }
        if route.page == .root {
            state?.rebuild(root: MenuModel.root(loginItem: loginItem, config: config,
                                                style: style, version: QuickMenu.version))
        }
        // Through the full path rather than straight to `render()`: a level that gained or lost
        // rows — the fetching note going away, a downloaded theme moving up into the installed
        // list — changes how tall the panel wants to be, and so does a new `font_size`.
        layoutAndRender()
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
            open(route: MenuRoute(page: page))
        case .toggleLoginItem:
            // Deliberately does not close: the value flips under the cursor, as omarchy-menu's
            // toggles do, so you can see what you just did.
            let setup = MenuModel.setup(loginItem: LoginItem.toggle(), config: config)
            // The level itself rather than a row of the root: Setup is not always in the same
            // place — Install and Remove come and go with the catalogue — and on the day the
            // toggle answers `unavailable` it is not there at all.
            if !setup.isEmpty { state?.replaceLevel(with: setup) }
            layoutAndRender()
        case .toggleSetting(let setting):
            // Same shape as the login toggle: the value flips under the cursor and the menu
            // stays. The flip goes through the config file and a reload, and that reload has
            // already handed the new config to `update` by the time the callback returns; the
            // level is rebuilt from the answer all the same — written into a copy of the config
            // first — so the row is right even if the reload found nothing to do.
            let on = onToggleSetting?(setting) ?? setting.value(in: config)
            var shown = config
            setting.set(on, in: &shown)
            state?.replaceLevel(with: MenuModel.setup(loginItem: loginItem, config: shown))
            layoutAndRender()
        case .run(let command):
            // Theme rows stay — `Command.keepsMenuOpen` says why at length. Everything else
            // goes: an `exec` brings another application forward and `quit` tears the process
            // down, and both want the panel gone and the keyboard handed back before they begin.
            //
            // Still dispatched a turn later either way, so the two paths differ in one thing
            // only. Escape or a click elsewhere closes the menu as it always did, and anything
            // it started carries on behind it; what it does not do is close by itself.
            if !command.keepsMenuOpen { close() }
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
        let wanted = route.page == .keybindings ? config.menu.listWidth : config.menu.width
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
            valueColumn: route.page == .keybindings ? 0.5 : nil,
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
        // re-centring mid-keystroke is a menu that jumps out from under the pointer. A Dock that
        // just hid itself is not that — the screens are where they were, one of them has a strip
        // back — and the menu stays where it is, which is where you are looking.
        add(NSApplication.didChangeScreenParametersNotification, object: nil) { [weak self] _ in
            guard let self, Self.currentScreenLayout != self.screenLayout else { return }
            self.close()
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
