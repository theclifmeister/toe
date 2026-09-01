import AppKit
import ApplicationServices
import ToeCore

final class ManagedWindow {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    var title: String?
    /// Where the window sat before it was stashed off-screen, so floating windows come back
    /// to exactly where they were.
    var frameBeforeStash: Box?
    var isStashed = false

    init(id: CGWindowID, element: AXUIElement, pid: pid_t,
         bundleID: String?, title: String?) {
        self.id = id
        self.element = element
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
    }
}

protocol WindowTrackerDelegate: AnyObject {
    func windowAppeared(_ window: ManagedWindow, shouldFloat: Bool)
    func windowDisappeared(_ id: CGWindowID)
    func windowFocused(_ id: CGWindowID)
    /// The window moved or resized without toe asking — an app restoring its own remembered
    /// geometry, or the user dragging it.
    func windowFrameChangedExternally(_ id: CGWindowID)
    func screensChanged()
    /// Something moved in the window stack that toe does not manage: another application came
    /// forward, or one opened a window toe will never tile. Neither changes the layout, but
    /// both change what is stacked over the focused window.
    func windowStackChanged()
}

/// Discovers windows and keeps them in sync with the running applications.
final class WindowTracker {

    weak var delegate: WindowTrackerDelegate?
    var floatRules: [FloatRule] = Config.defaultFloatRules

    private(set) var windows: [CGWindowID: ManagedWindow] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func window(_ id: CGWindowID) -> ManagedWindow? { windows[id] }

    // MARK: - Lifecycle

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appLaunched(_:)),
                              name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appTerminated(_:)),
                              name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appActivated(_:)),
                              name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }
    }

    @objc private func screensChanged() { delegate?.screensChanged() }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        observe(app)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        let pid = app.processIdentifier
        stopObserving(pid)
        for (id, window) in windows where window.pid == pid {
            windows.removeValue(forKey: id)
            delegate?.windowDisappeared(id)
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ownPID else { return }
        let element = AX.application(app.processIdentifier)
        if let focused = element.value(kAXFocusedWindowAttribute) {
            // swiftlint:disable:next force_cast
            if let id = (focused as! AXUIElement).windowID, windows[id] != nil {
                delegate?.windowFocused(id)
            }
        }
        // Unconditionally, and after the focus forwarding above rather than inside it: the app
        // coming forward is very often one toe manages nothing for — Raycast opening its
        // settings panel over the focused tile is the case that prompted this — and that is
        // exactly when the border needs to be told what is now stacked above it.
        noteStackChange()
    }

    /// Fires now and twice more shortly after. The notification arrives before the window
    /// server has necessarily finished raising and placing the window, and the border's depth
    /// is decided from stacking that is only true a beat later — the same reason `observe`
    /// sweeps for windows more than once, and bounded the same way.
    private func noteStackChange() {
        delegate?.windowStackChanged()
        for delay in [0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.delegate?.windowStackChanged()
            }
        }
    }

    // MARK: - Per-application observation

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ownPID, observers[pid] == nil else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return }
        observers[pid] = observer

        let element = AX.application(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXWindowCreatedNotification,
                             kAXFocusedWindowChangedNotification,
                             kAXApplicationActivatedNotification] {
            AXObserverAddNotification(observer, element, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        // Apps are frequently not AX-ready the instant they launch, so sweep a few times.
        adoptWindows(of: pid)
        for delay in [0.15, 0.4, 0.8, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.adoptWindows(of: pid)
            }
        }
    }

    /// The run-loop source has to come off the run loop as well as out of `observers`, or
    /// every launched-and-quit application leaves one behind for the life of the session.
    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func adoptWindows(of pid: pid_t) {
        let element = AX.application(pid)
        for window in element.windows { adopt(window, pid: pid) }
    }

    @discardableResult
    func adopt(_ element: AXUIElement, pid: pid_t) -> ManagedWindow? {
        guard isManageable(element) else { return nil }
        guard let id = element.windowID else { return nil }
        if let existing = windows[id] { return existing }

        let app = NSRunningApplication(processIdentifier: pid)
        let window = ManagedWindow(id: id, element: element, pid: pid,
                                   bundleID: app?.bundleIdentifier, title: element.title)
        windows[id] = window

        if let observer = observers[pid] {
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
            for notification in [kAXWindowMiniaturizedNotification,
                                 kAXWindowMovedNotification,
                                 kAXWindowResizedNotification] {
                AXObserverAddNotification(observer, element, notification as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
            }
        }

        let shouldFloat = floatRules.contains { $0.matches(bundleID: window.bundleID, title: window.title) }
        delegate?.windowAppeared(window, shouldFloat: shouldFloat)
        return window
    }

    /// Only ordinary, resizable, standard windows are tiled. Dialogs, sheets, palettes and
    /// anything that refuses a position or size are left exactly where the app put them —
    /// the conservative choice, and it keeps toe out of the way of system UI.
    private func isManageable(_ element: AXUIElement) -> Bool {
        guard element.role == kAXWindowRole else { return false }
        guard element.subrole == kAXStandardWindowSubrole else { return false }
        guard !element.isMinimized, !element.isFullscreen else { return false }
        guard element.isSettable(kAXPositionAttribute), element.isSettable(kAXSizeAttribute) else {
            return false
        }
        guard let size = element.size, size.width > 60, size.height > 60 else { return false }
        return true
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            // A window toe will never manage — a dialog, a sheet, a palette — still changes
            // what is stacked over the focused one. `adopt` returns the existing window when
            // it already knows it, so this only fires for windows nothing else reports.
            if adopt(element, pid: element.pid) == nil { noteStackChange() }

        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let id = windows.first(where: { CFEqual($0.value.element, element) })?.key else { return }
            delegate?.windowFrameChangedExternally(id)

        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            guard let id = windows.first(where: { CFEqual($0.value.element, element) })?.key else { return }
            windows.removeValue(forKey: id)
            delegate?.windowDisappeared(id)

        case kAXFocusedWindowChangedNotification:
            let window = adopt(element, pid: element.pid)
            if let id = window?.id ?? element.windowID, windows[id] != nil {
                delegate?.windowFocused(id)
            }

        case kAXApplicationActivatedNotification:
            let app = AX.application(element.pid)
            if let focused = app.value(kAXFocusedWindowAttribute) {
                // swiftlint:disable:next force_cast
                let focusedElement = focused as! AXUIElement
                let window = adopt(focusedElement, pid: element.pid)
                if let id = window?.id ?? focusedElement.windowID, windows[id] != nil {
                    delegate?.windowFocused(id)
                }
            }

        default:
            break
        }
    }
}

private func axCallback(observer: AXObserver, element: AXUIElement,
                        notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    tracker.handle(notification: notification as String, element: element)
}
