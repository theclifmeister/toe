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

    // MARK: - Start-up

    func start() {
        status.onReload = { [weak self] in self?.loadConfig() }
        status.onOpenConfig = { NSWorkspace.shared.open(Coordinator.configURL) }
        status.onOpenAccessibility = { Self.openAccessibilitySettings() }
        status.onQuit = { [weak self] in
            self?.unstashEverything()
            NSApp.terminate(nil)
        }

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
        status.update(workspace: workspaces.focusedWorkspaceIndex,
                      warnings: warnings,
                      accessibilityGranted: AXIsProcessTrusted())
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
        if shouldFloat {
            workspaces.floatingFrames[window.id] = window.element.frame
        }
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
        let settled = abs(have.x - want.x) < 2 && abs(have.y - want.y) < 2
            && abs(have.w - want.w) < 2 && abs(have.h - want.h) < 2
        if settled {
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

        for id in plan.restored {
            guard let window = tracker.window(id), window.isStashed else { continue }
            window.isStashed = false
            if let frame = window.frameBeforeStash {
                WindowMover.setFrame(frame, element: window.element, pid: window.pid)
            }
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
            if !workspaces.isFloating(id), let window = tracker.window(id) {
                workspaces.floatingFrames[id] = window.frameBeforeStash ?? window.element.frame
            }
            workspaces.toggleFloating(id)
            desired.removeValue(forKey: id)
        corrections.removeValue(forKey: id)
            apply(refocus: false)

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
