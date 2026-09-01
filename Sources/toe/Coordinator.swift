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
    private let status = StatusItem()
    private var watcher: ConfigWatcher?

    private var config = Config.makeDefault()
    private var warnings: [String] = []
    /// The frame each window is supposed to occupy, so a re-render does not churn every window.
    private var desired: [WindowID: Box] = [:]
    /// How many times we have re-asserted a frame an app pushed back on. Bounded, so a window
    /// with a minimum size larger than its tile is written once and then left alone rather
    /// than fought with forever.
    private var corrections: [WindowID: Int] = [:]
    private var focusApplied: WindowID?
    private var signalSources: [any DispatchSourceSignal] = []

    // MARK: - Start-up

    func start() {
        workspaces.cursorLocation = { Coordinates.toAX(NSEvent.mouseLocation) }
        status.workspaceProvider = { [weak self] in self?.workspaceSummaries() ?? [] }
        status.onSelectWorkspace = { [weak self] index in
            self?.dispatch(.workspace(.index(index)))
        }
        status.onSelectWindow = { [weak self] id in
            guard let self else { return }
            // Focusing a window on a hidden workspace should bring that workspace forward.
            if let index = self.workspaces.workspaceIndex(of: id),
               index != self.workspaces.focusedWorkspaceIndex {
                self.dispatch(.workspace(.index(index)))
            }
            self.focus(id)
        }
        status.onReload = { [weak self] in self?.loadConfig() }
        status.onOpenConfig = { NSWorkspace.shared.open(Coordinator.configURL) }
        status.onOpenAccessibility = { Self.openAccessibilitySettings() }
        status.onQuit = { [weak self] in
            self?.unstashEverything()
            NSApp.terminate(nil)
        }

        installSignalHandlers()
        writeDefaultConfigIfMissing()
        loadConfig()

        watcher = ConfigWatcher(url: Coordinator.configURL)
        watcher?.onChange = { [weak self] in self?.loadConfig() }
        watcher?.start()

        hotkeys.onTrigger = { [weak self] binding in self?.dispatch(binding.command) }

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
    /// would disappear. Unstash before going away, exactly as the Quit menu item does.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                self?.unstashEverything()
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
        tracker.delegate = self
        tracker.floatRules = config.floatRules
        refreshMonitors()
        tracker.start()
        refreshStatus()
        apply(refocus: false)
        Log.info("managing \(tracker.windows.count) window(s) across \(workspaces.monitors.count) monitor(s)")
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Config

    private func writeDefaultConfigIfMissing() {
        let url = Coordinator.configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Config.defaultTOML.write(to: url, atomically: true, encoding: .utf8)
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

        let rejected = hotkeys.register(newConfig.bindings)
        warnings += rejected.map { "\($0.source): already claimed by another app" }

        workspaces.options = newConfig.dwindle
        workspaces.gaps = newConfig.gaps
        tracker.floatRules = newConfig.floatRules
        border.apply(newConfig.border)

        refreshStatus()
        Log.info("config loaded: \(newConfig.bindings.count) binding(s), \(warnings.count) warning(s)")
        for warning in warnings { Log.error("config: \(warning)") }
        desired.removeAll()
        corrections.removeAll()          // gaps may have changed; re-write every frame
        apply(refocus: false)
    }

    private func refreshStatus() {
        status.update(workspaces: workspaceSummaries(),
                      warnings: warnings,
                      accessibilityGranted: AXIsProcessTrusted(),
                      showMonitorNames: workspaces.monitors.count > 1)
    }

    /// What the menu bar shows: every workspace, the applications on it, and which display
    /// (if any) is currently showing it.
    private func workspaceSummaries() -> [WorkspaceSummary] {
        let focusedIndex = workspaces.focusedWorkspaceIndex

        return (1...WorkspaceManager.workspaceCount).map { index in
            let ordered = workspaces.orderedWindows(inWorkspace: index)
            let groups = AppGrouping.group(ordered) { [weak self] id in
                self?.tracker.window(id)?.appName
            }
            let apps = groups.compactMap { group -> AppSummary? in
                guard let first = group.windows.first else { return nil }
                let icon = tracker.window(first)
                    .flatMap { NSRunningApplication(processIdentifier: $0.pid) }?.icon
                return AppSummary(name: group.name, windowCount: group.count,
                                  icon: icon, representativeWindow: first)
            }

            let showingOn = workspaces.monitorShowing(workspace: index)
            return WorkspaceSummary(
                index: index,
                isFocused: index == focusedIndex,
                isVisible: showingOn != nil,
                monitorName: showingOn.map { Self.monitorName(for: $0) },
                apps: apps)
        }
    }

    private static func monitorName(for displayID: UInt32) -> String {
        NSScreen.screens.first { $0.displayID == displayID }?.localizedName ?? "Display \(displayID)"
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
        // Adopt time is the only moment a window's own geometry is known — the first tile
        // write clobbers it. This is Hyprland's `m_vLastFloatingSize` / `..Position`, and it
        // is what a window returns to the first time you float it.
        workspaces.floatingFrames[window.id] = window.element.frame
        workspaces.addWindow(window.id, floating: shouldFloat)
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
        guard workspaces.workspaceIndex(of: id) != nil else { return }
        workspaces.noteFocus(id)
        focusApplied = id
        updateBorder()
        refreshStatus()
    }

    /// Chromium, Electron and the JetBrains IDEs restore their own remembered geometry a beat
    /// after the window is created, clobbering the frame toe just wrote. Re-asserting on the
    /// move/resize notification is what actually makes those apps tile — and it doubles as
    /// snap-back when a window is dragged out of its tile.
    func windowFrameChangedExternally(_ id: WindowID) {
        guard let window = tracker.window(id), !window.isStashed else { return }

        if workspaces.isFloating(id) {
            workspaces.floatingFrames[id] = window.element.frame
            if id == workspaces.focusedWindow { updateBorder() }
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
            WindowMover.setFrame(box, element: window.element, pid: window.pid)
        }

        if refocus, let target = plan.focus, target != focusApplied,
           let window = tracker.window(target) {
            focusApplied = target
            WindowMover.focus(window)
        }

        updateBorder()
        refreshStatus()
    }

    private func updateBorder() {
        guard config.border.enabled,
              let focused = workspaces.focusedWindow,
              let window = tracker.window(focused),
              !window.isStashed
        else {
            border.hide()
            return
        }
        // Prefer the frame we wrote; fall back to asking the window for floating ones.
        if let box = window.element.frame ?? desired[focused] {
            border.show(around: box)
        } else {
            border.hide()
        }
    }

    private func unstashEverything() {
        for window in tracker.windows.values where window.isStashed {
            window.isStashed = false
            if let frame = window.frameBeforeStash {
                WindowMover.setFrame(frame, element: window.element, pid: window.pid)
            }
        }
    }

    // MARK: - Dispatch

    private func focus(_ id: WindowID) {
        guard let window = tracker.window(id) else { return }
        workspaces.noteFocus(id)
        focusApplied = id
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
        }
    }
}
