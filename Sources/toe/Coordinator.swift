import AppKit
import ApplicationServices
import ToeCore

/// Wires the layout engine to the screen: window events in, frames and focus out.
final class Coordinator: WindowTrackerDelegate {

    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/toe/toe.toml")

    private let workspaces = WorkspaceManager()
    private let tracker = WindowTracker()
    private let hotkeys = HotkeyManager()
    private let border = BorderOverlay()
    private let drag = DragMonitor()
    private let dockSwipes = DockSwipeTap()
    private let hideBlocker = HideBlocker()
    private let status = StatusItem()
    private let quickMenu = QuickMenu()
    private var watcher: ConfigWatcher?

    private var config = Config.makeDefault()
    private var warnings: [String] = []
    /// Problems that are not the config's fault and so must survive a reload — a tap that would
    /// not create, for instance. `warnings` is replaced wholesale on every load.
    private var runtimeWarnings: [String] = []
    /// False until Accessibility has landed and `beginManaging()` has run. A config reload before
    /// that must not try to create the event tap: it would be refused and never retried.
    private var isManaging = false
    /// The frame each window is supposed to occupy, so a re-render does not churn every window.
    private var desired: [WindowID: Box] = [:]
    /// How many times we have re-asserted a frame an app pushed back on. Bounded, so a window
    /// with a minimum size larger than its tile is written once and then left alone rather
    /// than fought with forever.
    private var corrections: [WindowID: Int] = [:]
    private var focusApplied: WindowID?
    /// Windows toe raised itself, and when — see `isEchoOfOwnRaise`.
    private var selfRaised: [WindowID: TimeInterval] = [:]
    /// How long a focus notification can still be the echo of one of those raises.
    ///
    /// Generous, because the cost of getting this wrong runs the two ways round very
    /// differently. An echo let through is recorded as a focus change that never happened, and
    /// toe then works from a window the user is not on — `movefocus` walks from the wrong
    /// place, and the border sits on the wrong window until something corrects it. A click let
    /// through late is one focus change toe hears about a beat later than it might have.
    /// Applications answer a raise in milliseconds when they are idle and take their time when
    /// they are not, so this is set for the slow ones.
    private static let raiseEchoWindow: TimeInterval = 1.2
    /// True from the moment a snapshot is restored until the windows it named have had their
    /// chance to turn up. Saving is suspended meanwhile: a snapshot taken halfway through
    /// adoption would record a layout missing most of its windows, over the top of the good
    /// one.
    private var isSettlingSession = false
    /// Pending debounced write. See `scheduleSessionSave`.
    private var sessionSave: DispatchWorkItem?
    /// The window the user has hold of. Its frame is theirs until they let go: toe neither
    /// re-asserts its tile nor writes it a new one, the same courtesy `apply` already extends
    /// to a floating window.
    private var draggedWindow: WindowID? { drag.isDragging ? drag.window : nil }
    private var signalSources: [any DispatchSourceSignal] = []

    // MARK: - Start-up

    func start() {
        workspaces.cursorLocation = { Coordinates.toAX(NSEvent.mouseLocation) }
        status.onSelectWorkspace = { [weak self] index in
            self?.dispatch(.workspace(.index(index)))
        }
        status.onOpenAccessibility = { Self.openAccessibilitySettings() }
        status.onOpenMenu = { [weak self] in self?.dispatch(.menu(.root)) }

        installSignalHandlers()
        // Symbolic hotkey state outlives the process, so a previous toe that was killed rather
        // than quit may have left Mission Control's shortcut switched off. Give it back before
        // anything else, so the config below decides from a known-good baseline.
        SymbolicHotkeys.repairAfterUncleanExit()
        // Same reasoning, same shape: the reveal-desktop preference is the window server's, not
        // toe's, so a copy that was killed rather than quit may have left it switched off.
        WallpaperClick.repairAfterUncleanExit()
        writeDefaultConfigIfMissing()
        loadConfig()

        watcher = ConfigWatcher(url: Coordinator.configURL)
        watcher?.onChange = { [weak self] in self?.loadConfig() }
        watcher?.start()

        hotkeys.onTrigger = { [weak self] binding in
            guard let self else { return }
            // A Carbon hotkey is resolved system-wide, ahead of whichever window has the
            // keyboard — including toe's own menu. That is what lets a second SUPER+SPACE close
            // the menu rather than typing a space into its filter, and it is also why everything
            // else has to be held back: SUPER+W while the menu is up would close a window the
            // user cannot see. `quit` stays live so a wedged menu can never trap anyone, which is
            // the reasoning behind `Config.fallbackBindings` as well.
            if self.quickMenu.isVisible {
                switch binding.command {
                case .menu, .quit: break
                default: return
                }
            }
            self.dispatch(binding.command)
        }
        quickMenu.onCommand = { [weak self] command in self?.dispatch(command) }
        // Dragging a tiled window over another one trades their places, live, the way
        // Hyprland's `IHyprLayout::onMouseMove` does.
        drag.onMove = { [weak self] id, point in
            guard let self, self.workspaces.swapWithWindow(at: point, dragging: id) else { return }
            self.apply(refocus: false)
        }
        drag.onEnd = { [weak self] id in self?.endDrag(id) }
        hideBlocker.onRestored = { [weak self] pid in self?.relayoutAfterUnhide(pid) }

        guard waitForAccessibility() else {
            Log.error("no Accessibility permission — hotkeys are live but windows cannot be moved. "
                      + "Grant it in System Settings › Privacy & Security › Accessibility, "
                      + "or run `make reset-perms` after a rebuild.")
            return
        }
        beginManaging()
    }

    /// `make run` restarts toe with `pkill`, and SIGTERM's default action would leave a hidden
    /// workspace's windows parked in the stash corner. The next launch then adopts them there
    /// and records that corner as the frame to float them back to — so a window you floated
    /// would disappear. Unstash before going away, exactly as `quit` does.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutDown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// toe is useless without Accessibility, but it should not die either — it keeps its menu
    /// bar item and starts the moment the permission is granted.
    private func waitForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return true }

        refreshStatus()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            Log.info("Accessibility granted")
            self?.beginManaging()
        }
        return false
    }

    private func beginManaging() {
        // Before the first AX call: caps how long any single one can block the main thread.
        AX.setGlobalMessagingTimeout()
        isManaging = true
        tracker.delegate = self
        tracker.floatRules = config.floatRules
        refreshMonitors()
        restoreSession()
        tracker.start()
        settleSession()
        // Deliberately here and not in `start()`: a filtering event tap needs the Accessibility
        // grant, and it is refused outright — never retried — without one. This is the first
        // point at which the grant is known to exist, whether it was already there or has just
        // been given, so a first run picks the tap up without a relaunch.
        applyDockSwipeSetting()
        applyMiscSettings()
        applySessionSetting()
        refreshStatus()
        apply(refocus: false)
        Log.info("managing \(tracker.windows.count) window(s) across \(workspaces.monitors.count) monitor(s)")
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Config

    /// Writes the shipped default on first run, for this user only.
    ///
    /// This file is executable code, not merely settings: an `exec` binding runs `/bin/sh -c`
    /// with whatever it says, about 150 ms after it changes, inside a login agent holding the
    /// Accessibility grant. So the mode is set here rather than inherited from whatever umask
    /// happens to be in effect, and a failure is named rather than swallowed — a first run
    /// that could not write its config used to behave exactly like one that had, leaving you
    /// looking for a file that was never created.
    private func writeDefaultConfigIfMissing() {
        let url = Coordinator.configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            Log.error("could not create \(url.deletingLastPathComponent().path): \(error.localizedDescription)")
            return
        }

        // open with O_EXCL rather than a write through FileManager, for two reasons: it
        // refuses rather than following a symlink already sitting at that path, and it is one
        // call that both creates the file and fixes its mode, so the file never exists at the
        // umask's mode even briefly.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            Log.error("could not create \(url.path): \(String(cString: strerror(errno)))")
            return
        }
        defer { close(fd) }

        let bytes = Data(Config.defaultTOML.utf8)
        let written = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if written != bytes.count {
            Log.error("could not write \(url.path): \(String(cString: strerror(errno)))")
        }
    }

    /// Names a config file that other people can rewrite, or that belongs to someone else.
    ///
    /// A warning and not a refusal: symlinking this file into a dotfiles repository is how a
    /// good many people manage it, and refusing to load a symlink would break every one of
    /// them. `stat` rather than `lstat` for exactly that reason — what runs is the file at the
    /// end of the link, so that is the file whose permissions matter.
    private static func permissionWarning(for url: URL) -> String? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let name = url.lastPathComponent
        if info.st_uid != getuid() {
            return "\(name) belongs to uid \(info.st_uid), not to you — whoever owns it can run commands as you"
        }
        if info.st_mode & (S_IWGRP | S_IWOTH) != 0 {
            let mode = String(info.st_mode & 0o777, radix: 8)
            return "\(name) is mode \(mode), writable by other users — it runs shell commands, so chmod 600 it"
        }
        return nil
    }

    private func loadConfig() {
        let text = (try? String(contentsOf: Coordinator.configURL, encoding: .utf8)) ?? Config.defaultTOML
        let newConfig: Config
        do {
            newConfig = try Config.parse(text)
        } catch {
            // Keep running on the last good config — a typo must never cost you your keyboard.
            warnings = ["\(Coordinator.configURL.lastPathComponent) \(error)"]
            refreshStatus()
            Log.error("config error, keeping the previous config: \(error)")
            return
        }

        config = newConfig
        warnings = newConfig.warnings
        if let warning = Coordinator.permissionWarning(for: Coordinator.configURL) {
            warnings.append(warning)
        }

        let rejected = hotkeys.register(newConfig.bindings)
        warnings += rejected.map { "\($0.source): already claimed by another app" }

        workspaces.options = newConfig.dwindle
        workspaces.gaps = newConfig.gaps
        workspaces.floatingSize = newConfig.floating
        tracker.floatRules = newConfig.floatRules
        border.apply(newConfig.border)
        status.persistentWorkspaces = newConfig.bar.persistentWorkspaces
        applyDockSwipeSetting()
        applyMiscSettings()
        applySessionSetting()

        refreshStatus()
        Log.info("config loaded: \(newConfig.bindings.count) binding(s), \(warnings.count) warning(s)")
        for warning in warnings { Log.error("config: \(warning)") }
        desired.removeAll()
        corrections.removeAll()          // gaps may have changed; re-write every frame
        apply(refocus: false)
    }

    /// Starts and stops the dock swipe tap as the config flips, on every reload as well as at
    /// startup. A no-op until Accessibility has landed; `beginManaging()` calls it again then.
    private func applyDockSwipeSetting() {
        guard isManaging else { return }
        runtimeWarnings.removeAll()

        guard config.gestures.swallowDockSwipes else {
            dockSwipes.stop()
            return
        }
        if !dockSwipes.isRunning, !dockSwipes.start() {
            runtimeWarnings = ["dock swipe tap could not be created — swipes are not swallowed"]
        }
    }

    /// The macOS behaviours toe takes over, applied at startup and on every reload. None of them
    /// needs Accessibility, but all are gated on `isManaging` so they arrive together with the
    /// tap rather than flickering on before toe can actually manage anything.
    private func applyMiscSettings() {
        guard isManaging else { return }

        if config.misc.disableExposeShortcuts {
            SymbolicHotkeys.disable(SymbolicHotkeys.expose)
        } else {
            SymbolicHotkeys.restoreAll()
        }

        if config.misc.disableWallpaperClick {
            WallpaperClick.disable()
        } else {
            WallpaperClick.restore()
        }

        if config.misc.preventHiding {
            hideBlocker.start()
        } else {
            hideBlocker.stop()
        }
    }

    /// Puts the layout and the focus back after an application toe unhid has returned.
    ///
    /// A hidden window keeps the frame it had, so `desired` still matches it and `apply` would
    /// write nothing — which is what leaves the windows looking wrong once they are back. Dropping
    /// this application's bookkeeping forces its tiles to be written again, and the correction
    /// budget goes with it, because coming back from a hide is not an app fighting for its own
    /// geometry.
    private func relayoutAfterUnhide(_ pid: pid_t) {
        for (id, window) in tracker.windows where window.pid == pid {
            desired.removeValue(forKey: id)
            corrections.removeValue(forKey: id)
        }
        apply(refocus: false)

        // `activate()` gave the application back the foreground; this gives the focus back to the
        // window that had it. Deliberately not `focusApplied`: hiding an application makes macOS
        // activate whichever one is behind it, and that activation reaches toe as an ordinary
        // focus change — often before the hide notification does — so by now `focusApplied` names
        // a window belonging to some other app. `focusHistory` is most-recent-first and survives
        // that, so asking it for this application's own last-focused window is race-free.
        if let id = workspaces.focusHistory.first(where: { tracker.window($0)?.pid == pid }) {
            focus(id)
        }
    }

    private func refreshStatus() {
        status.update(workspaces: workspaceStates(),
                      warnings: warnings + runtimeWarnings,
                      accessibilityGranted: AXIsProcessTrusted())
    }

    /// What the strip in the menu bar title draws. This runs on every focus change and every
    /// adopted window, so it stays to what the strip actually reads — no window lists, no app
    /// names, and above all no icons.
    private func workspaceStates() -> [WorkspaceStrip.State] {
        let focusedIndex = workspaces.focusedWorkspaceIndex

        return (1...WorkspaceManager.workspaceCount).map { index in
            WorkspaceStrip.State(index: index,
                                 isFocused: index == focusedIndex,
                                 isVisible: workspaces.monitorShowing(workspace: index) != nil,
                                 isEmpty: workspaces.isEmpty(workspace: index))
        }
    }

    // MARK: - Monitors

    private func refreshMonitors() {
        let monitors = NSScreen.screens.map { screen in
            Monitor(id: screen.displayID,
                    frame: Coordinates.toAX(screen.frame),
                    usable: Coordinates.toAX(screen.visibleFrame))
        }
        guard !monitors.isEmpty else { return }
        workspaces.setMonitors(monitors)
    }

    /// Where a hidden workspace's windows are parked. See `Stash.origin` — this needs no
    /// private API, and the trade-off is that stashed windows stay visible to Cmd-Tab.
    private func stashPoint(for window: ManagedWindow) -> CGPoint {
        let index = workspaces.workspaceIndex(of: window.id)
        let monitorID = index.flatMap { workspaces.workspaces[$0]?.monitorID } ?? workspaces.focusedMonitorID
        guard let monitor = workspaces.monitor(id: monitorID) else { return .zero }
        let size = window.element.size ?? CGSize(width: monitor.usable.w, height: monitor.usable.h)
        let origin = Stash.origin(windowSize: Point(x: size.width, y: size.height),
                                  on: monitor, monitors: workspaces.monitors)
        return CGPoint(x: origin.x, y: origin.y)
    }

    // MARK: - WindowTrackerDelegate

    func windowAppeared(_ window: ManagedWindow, shouldFloat: Bool) {
        // A window a restored session already placed is left exactly as the snapshot has it:
        // its workspace, its slot in the tree, and the floating frame it was remembered with,
        // which is better than the frame it happens to be wearing now — that one is the tile
        // toe gave it before the restart.
        if workspaces.workspaceIndex(of: window.id) == nil {
            // Adopt time is the only moment a window's own geometry is known — the first tile
            // write clobbers it. This is Hyprland's `m_vLastFloatingSize` / `..Position`, and it
            // is what a window returns to the first time you float it.
            workspaces.floatingFrames[window.id] = window.element.frame
            workspaces.addWindow(window.id, floating: shouldFloat)
        }
        apply(refocus: false)
        refreshStatus()
    }

    func windowDisappeared(_ id: WindowID) {
        workspaces.removeWindow(id)
        workspaces.floatingFrames.removeValue(forKey: id)
        desired.removeValue(forKey: id)
        corrections.removeValue(forKey: id)
        if focusApplied == id { focusApplied = nil }
        apply(refocus: false)
    }

    func windowFocused(_ id: WindowID) {
        guard workspaces.workspaceIndex(of: id) != nil, !isEchoOfOwnRaise(id) else { return }
        workspaces.noteFocus(id)
        focusApplied = id
        // Clicking a window raises it, so the focused one is already in front and stays there;
        // this is only about the float it has just taken the focus from.
        sinkUnfocusedFloats(workspaces.render())
        updateBorder()
        refreshStatus()
        scheduleSessionSave()
    }

    /// Chromium, Electron and the JetBrains IDEs restore their own remembered geometry a beat
    /// after the window is created, clobbering the frame toe just wrote. Re-asserting on the
    /// move/resize notification is what actually makes those apps tile — and it doubles as
    /// snap-back when a window is dragged out of its tile.
    func windowFrameChangedExternally(_ id: WindowID) {
        guard let window = tracker.window(id), !window.isStashed else { return }
        // A move the user is making by hand hides the border until they let go; see DragMonitor.
        if id == workspaces.focusedWindow { drag.noteExternalFrameChange(id) }

        if workspaces.isFloating(id) {
            workspaces.floatingFrames[id] = window.element.frame
            if id == workspaces.focusedWindow { updateBorder() }
            return
        }

        // A tile is re-asserted against an app that fights it, never against the user. Where the
        // window has got to during the drag says nothing about where it belongs — the pointer
        // decides that, in `swapWithWindow` — so leave it alone until they let go. The border
        // still gets a look in: this is where it drops behind the window at the start of a drag,
        // and where it re-takes that place if the app raises itself mid-drag.
        if id == draggedWindow {
            updateBorder()
            return
        }

        guard let want = desired[id], let have = window.element.frame else { return }
        if Self.settled(have, want) {
            corrections[id] = 0
            if id == workspaces.focusedWindow { updateBorder() }
            return
        }

        let attempts = corrections[id, default: 0]
        guard attempts < 3 else { return }   // the app will not comply; stop fighting it
        corrections[id] = attempts + 1
        WindowMover.setFrame(want, element: window.element, pid: window.pid)
        if id == workspaces.focusedWindow { updateBorder() }
    }

    /// Apps round and clamp the frames they are given; two frames within 2pt of each other are
    /// the same frame as far as toe is concerned.
    private static func settled(_ a: Box, _ b: Box) -> Bool {
        abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2 && abs(a.w - b.w) < 2 && abs(a.h - b.h) < 2
    }

    func screensChanged() {
        refreshMonitors()
        desired.removeAll()
        corrections.removeAll()
        apply(refocus: false)
    }

    /// Nothing about the layout has changed — only what is stacked over the focused window,
    /// which is what decides whether the border can sit above everything.
    func windowStackChanged() {
        // Somebody else has re-ordered the stack — most often an application coming forward,
        // which brings all of its windows with it, float included. That is the one thing toe
        // cannot predict from its own state, so the floats are put back down from what the
        // window server says is up there now, before the border is asked where it belongs.
        sinkUnfocusedFloats(workspaces.render())
        updateBorder()
    }

    // MARK: - Applying the layout

    private func apply(refocus: Bool) {
        let plan = workspaces.render()

        for id in plan.stashed {
            guard let window = tracker.window(id), !window.isStashed else { continue }
            window.frameBeforeStash = window.element.frame
            window.isStashed = true
            desired.removeValue(forKey: id)
            corrections.removeValue(forKey: id)
            WindowMover.setPosition(stashPoint(for: window), element: window.element, pid: window.pid)
        }

        // Floating frames deliberately bypass `desired` / `corrections`: that machinery exists
        // to re-assert a tile against an app that fights it, and pointing it at a floating
        // window would fight the user's own drags instead. Writing only on a real difference
        // makes this a no-op on every render but the one that changed something — floating a
        // window, bringing its workspace back, or losing the display it was remembered on.
        for (id, box) in plan.floating {
            guard let window = tracker.window(id) else { continue }
            window.isStashed = false
            if let have = window.element.frame, Self.settled(have, box) { continue }
            WindowMover.setFrame(box, element: window.element, pid: window.pid)
        }

        for (id, box) in plan.frames {
            guard let window = tracker.window(id) else { continue }
            window.isStashed = false
            guard desired[id] != box else { continue }
            desired[id] = box
            corrections[id] = 0
            // Writing this one would yank it out from under the cursor mid-drag; `endDrag`
            // puts it in its tile once the drag is over. Its swap partner moves normally,
            // and that is the feedback the user sees.
            if id == draggedWindow { continue }
            WindowMover.setFrame(box, element: window.element, pid: window.pid)
        }

        sinkUnfocusedFloats(plan)

        if refocus, let target = plan.focus, target != focusApplied,
           let window = tracker.window(target) {
            focusApplied = target
            WindowMover.focus(window)
        }

        updateBorder()
        refreshStatus()
        scheduleSessionSave()
    }

    private func updateBorder() {
        guard config.border.enabled,
              let focused = draggedWindow ?? workspaces.focusedWindow,
              let window = tracker.window(focused),
              !window.isStashed
        else {
            border.hide()
            return
        }

        // While the user has hold of a window the border marks the tile it will land in rather
        // than the window itself. Two reasons, and they point the same way: toe hears about the
        // window's own movement through Accessibility, well behind the fact, so a border chasing
        // it would trail across the screen — and the tile is the useful thing to show anyway,
        // because the swap has already happened and that is where letting go puts it. A floating
        // window has no tile, so it keeps the old behaviour of no border until it is dropped.
        if focused == draggedWindow {
            // Behind the window being dragged, and above every other one — where Hyprland puts
            // it, since it draws each border with its own window and the focused window last.
            if let tile = desired[focused] {
                border.show(around: tile, of: focused, depth: .behindFrontmost)
            } else {
                border.hide()
            }
            return
        }

        // Prefer the frame we wrote; fall back to asking the window for floating ones.
        if let box = window.element.frame ?? desired[focused] {
            border.show(around: box, of: focused, depth: borderDepth(around: box, of: focused))
        } else {
            border.hide()
        }
    }

    /// Where the border belongs in the stack.
    ///
    /// Above every ordinary window is right almost always — but a `.floating` panel is
    /// composited above every ordinary window whatever the real z-order says, so a dialog
    /// opened over the focused window had the ring drawn straight through it. When something
    /// really is stacked over the band, the ordinary level puts the border back underneath the
    /// active application, where it belongs: still above every inactive app, so the ring stays
    /// visible all the way round, with the window in front covering only what it overlaps.
    private func borderDepth(around box: Box, of id: WindowID) -> BorderOverlay.Depth {
        let above = WindowStack.ordinaryWindowsAbove(id)
        return BorderGeometry.bandIsCovered(window: box, width: config.border.width, by: above)
            ? .behindFrontmost : .aboveEverything
    }

    /// Sends every floating window that has lost the focus behind the tiles it covers.
    ///
    /// `togglefloating` raises a float, and focusing it raises it again — right while it is the
    /// window in hand, wrong the moment the focus moves on, because the float was then left
    /// sitting over half of whichever tile the focus had moved to. Accessibility has no lower
    /// action, so the way down is to raise what the float covers; see `Stacking.raiseOrder`,
    /// which works out the shortest set of raises that gets there.
    ///
    /// Not while a window is being dragged: the stack the user is looking at then is one they
    /// are making themselves, and the drag ends in an `apply` that settles it anyway.
    private func sinkUnfocusedFloats(_ plan: RenderPlan) {
        guard draggedWindow == nil else { return }
        // One focus change reaches this several ways over — the command, the notification the
        // application sends back, the render that follows — so the order is worked out against
        // the stack as it really is, and a float already at the bottom asks for no raises at
        // all. Without that, the repeats are what the user sees as flicker.
        let order = Stacking.raiseOrder(tiles: plan.frames,
                                        floats: plan.floating,
                                        focused: workspaces.focusedWindow,
                                        stackedAbove: WindowStack.windowsAbove)
        guard !order.isEmpty else { return }

        let now = ProcessInfo.processInfo.systemUptime
        selfRaised = selfRaised.filter { now - $0.value < Self.raiseEchoWindow }
        for id in order {
            guard let window = tracker.window(id), !window.isStashed else { continue }
            selfRaised[id] = now
            WindowMover.raise(window)
        }
    }

    /// Whether a focus notification is toe's own restacking coming back at it.
    ///
    /// Raising a window makes it its application's focused window, and the notification that
    /// arrives is the very one a click produces — nothing in it tells the two apart. Taken at
    /// face value it is a loop: toe hands the focus to a window it only meant to re-order, that
    /// focus sinks a float, sinking raises more windows, and every one of those reports a focus
    /// change of its own. The window toe is focusing for real is the exception — it is raised
    /// on purpose, and its echo is the truth.
    private func isEchoOfOwnRaise(_ id: WindowID) -> Bool {
        guard id != focusApplied, let raisedAt = selfRaised[id] else { return false }
        // Raising a window does not bring its application forward, so a window toe raised that
        // reports the focus from an application which is not the frontmost one is an echo
        // however long it took to arrive. A click is never that: it activates as it focuses.
        if let window = tracker.window(id),
           NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid {
            return true
        }
        guard ProcessInfo.processInfo.systemUptime - raisedAt < Self.raiseEchoWindow else {
            selfRaised.removeValue(forKey: id)
            return false
        }
        return true
    }

    /// The user has let go. The window has been off its tile for the length of the drag, so
    /// clearing `desired` is what makes `apply` write it into whichever tile it now owns —
    /// its own, if the drag never crossed another one. `apply` ends in `updateBorder`, which
    /// brings the focus border back now that the drag is over.
    private func endDrag(_ id: WindowID) {
        desired.removeValue(forKey: id)
        corrections.removeValue(forKey: id)
        apply(refocus: false)
    }

    /// Everything that must happen before toe goes away, whichever way it is going: the Quit menu
    /// item, or SIGTERM, which is how `make run` replaces a running copy. There is no
    /// `applicationWillTerminate` — `NSApp.terminate` and `exit(0)` are both reached from here, so
    /// this is the one teardown path.
    private func shutDown() {
        // First, and before `unstashEverything` starts moving windows around: this is the one
        // write that matters, since it is the one a deliberate restart depends on.
        saveSession()
        unstashEverything()
        // A filtering tap left registered against a callback that is about to go away spins
        // WindowServer, so it is taken down deliberately rather than left to process death.
        dockSwipes.stop()
        hideBlocker.stop()
        // The two that would otherwise outlive toe: the window server keeps a symbolic hotkey
        // switched off until something switches it back on, and the reveal-desktop preference is
        // written to the user's settings.
        SymbolicHotkeys.restoreAll()
        WallpaperClick.restore()
    }

    private func unstashEverything() {
        for window in tracker.windows.values where window.isStashed {
            window.isStashed = false
            if let frame = window.frameBeforeStash {
                WindowMover.setFrame(frame, element: window.element, pid: window.pid)
            }
        }
    }

    // MARK: - Session

    /// Puts back the layout the last run left behind.
    ///
    /// Before `tracker.start()`, deliberately: the applications are still running, so their
    /// windows come back through Accessibility over the second that follows, and the tree has
    /// to be waiting for them rather than built around them as they arrive. A window the
    /// snapshot placed is recognised in `windowAppeared` and left exactly where it was.
    private func restoreSession() {
        // Held until `settleSession`, whether or not there was anything to restore, so the
        // first snapshot of a fresh run is not taken mid-adoption either.
        isSettlingSession = true
        guard config.misc.restoreSession, let snapshot = SessionStore.load() else { return }

        let byKey = Dictionary(monitorKeys().map { ($0.value, $0.key) },
                               uniquingKeysWith: { first, _ in first })
        workspaces.restore(snapshot, monitorID: { byKey[$0] })

        let restored = workspaces.workspaces.values.reduce(0) { $0 + $1.windows.count }
        Log.info("session restored: \(restored) window(s) across "
                 + "\(workspaces.workspaces.values.filter { !$0.isEmpty }.count) workspace(s)")
    }

    /// Clears out whatever the snapshot named that has not turned up.
    ///
    /// The tracker sweeps each application at 0.15, 0.4, 0.8 and 1.5 seconds, because apps are
    /// frequently not AX-ready the instant they launch. Past the last of those, a window still
    /// missing is one that no longer exists — an application quit while toe was down — and
    /// dropping it collapses the tree around the gap the way losing it live would have. Until
    /// then a tile with nothing behind it costs nothing: `apply` skips every id the tracker
    /// does not know.
    private func settleSession() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            self.isSettlingSession = false
            if self.workspaces.reap(keeping: Set(self.tracker.windows.keys)) {
                self.apply(refocus: false)
            }
            self.saveSession()
        }
    }

    /// Debounced, because `apply` runs on every layout change and a focus change is a layout
    /// change as far as the snapshot is concerned. The write that actually matters is the one
    /// in `shutDown`; this is the one that covers the ways toe can go away without reaching it
    /// — a crash, or `kill -9`.
    private func scheduleSessionSave() {
        guard isManaging, !isSettlingSession, config.misc.restoreSession else { return }
        sessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSession() }
        sessionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func saveSession() {
        sessionSave?.cancel()
        sessionSave = nil
        // Quitting while the session is still settling deliberately writes nothing: the file
        // already on disk is the good one, and what is in memory right now is half of it.
        guard isManaging, !isSettlingSession, config.misc.restoreSession else { return }

        let keys = monitorKeys()
        SessionStore.save(workspaces.snapshot(boot: SessionStore.bootToken,
                                              monitorKey: { keys[$0] }))
    }

    /// Turning the session off should not leave a stale layout on disk that toe will never
    /// read again.
    private func applySessionSetting() {
        guard !config.misc.restoreSession else { return }
        sessionSave?.cancel()
        sessionSave = nil
        SessionStore.clear()
    }

    /// A durable name for each live display, asked again every time rather than cached:
    /// `CGDirectDisplayID` is handed out per connection, so the mapping changes under us
    /// whenever a monitor is plugged or unplugged.
    private func monitorKeys() -> [UInt32: String] {
        var out: [UInt32: String] = [:]
        for monitor in workspaces.monitors {
            if let key = SessionStore.monitorKey(monitor.id) { out[monitor.id] = key }
        }
        return out
    }

    // MARK: - Dispatch

    private func focus(_ id: WindowID) {
        guard let window = tracker.window(id) else { return }
        workspaces.noteFocus(id)
        focusApplied = id
        // Before the focus, not after: this raises the tiles a float has stopped being
        // entitled to cover, and doing it afterwards would raise them over the very window
        // that is being focused.
        sinkUnfocusedFloats(workspaces.render())
        WindowMover.focus(window)
        updateBorder()
        refreshStatus()
    }

    func dispatch(_ command: Command) {
        switch command {
        case .moveFocus(let direction):
            if let target = workspaces.windowInDirection(direction) { focus(target) }

        case .swapWindow(let direction):
            if workspaces.swapWindow(direction) { apply(refocus: false) }

        case .moveWindow(let direction):
            if workspaces.moveWindow(direction) { apply(refocus: false) }

        case .workspace(let target):
            switch target {
            case .index(let n): workspaces.switchTo(workspace: n)
            case .next: workspaces.switchToRelativeWorkspace(1)
            case .previous: workspaces.switchToRelativeWorkspace(-1)
            case .former: workspaces.switchToPreviousWorkspace()
            }
            apply(refocus: true)

        case .moveToWorkspace(let n, let follow):
            workspaces.moveFocusedWindow(toWorkspace: n, follow: follow)
            apply(refocus: follow)

        case .killActive:
            guard let id = workspaces.focusedWindow, let window = tracker.window(id) else { return }
            WindowMover.close(window)

        case .toggleFloating:
            guard let id = workspaces.focusedWindow else { return }
            workspaces.toggleFloating(id)
            desired.removeValue(forKey: id)
            corrections.removeValue(forKey: id)
            apply(refocus: false)
            // A floating window belongs above the tiles. AX has no persistent always-on-top,
            // so raise it now; focusing it later raises it again.
            if workspaces.isFloating(id), let window = tracker.window(id) {
                WindowMover.focus(window)
                focusApplied = id
            }

        case .toggleSplit:
            guard let id = workspaces.focusedWindow,
                  let index = workspaces.workspaceIndex(of: id) else { return }
            workspaces.workspaces[index]?.layout.toggleSplit(id)
            apply(refocus: false)

        case .swapSplit:
            guard let id = workspaces.focusedWindow,
                  let index = workspaces.workspaceIndex(of: id) else { return }
            workspaces.workspaces[index]?.layout.swapSplit(id)
            apply(refocus: false)

        case .exec(let commandLine):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", commandLine]
            try? process.run()

        case .reload:
            loadConfig()

        case .editConfig:
            openConfigInTerminal()

        case .menu(let page):
            quickMenu.toggle(page: page, config: config,
                             usable: workspaces.monitor(id: workspaces.focusedMonitorID)?.usable)

        case .quit:
            shutDown()
            NSApp.terminate(nil)
        }
    }

    /// The config has no window of its own and, since the menu bar item lost its menu, no
    /// menu item either — so `editconfig` opens it the way you would edit it anyway: a
    /// terminal with nano in it. Terminal.app rather than the terminal you launch with
    /// SUPER+ENTER, because it is the one that is always installed; bind `exec` instead if
    /// you want your own (there is a line for it in the default config).
    private func openConfigInTerminal() {
        let shell = "nano '" + Coordinator.configURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let quoted = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            tell application "Terminal"
                activate
                do script "\(quoted)"
            end tell
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
        } catch {
            Log.error("editconfig: could not open Terminal: \(error)")
        }
    }
}
