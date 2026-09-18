import AppKit
import ApplicationServices
import ToeCore

/// The ordinary application an accessory helper's windows belong to (#158).
///
/// Two handles rather than one, because Steam's are two different things. `application` is
/// the `NSRunningApplication` for `com.valvesoftware.steam`, the record with the name, the
/// bundle identifier, the activation policy and the `terminate()` that quits Steam — and a
/// `processIdentifier` of −1, because Steam's launcher execs into `steam_osx` and
/// LaunchServices keeps a record with no pid. `pid` is `steam_osx` itself, read from the
/// helper's parent, and is the one Accessibility can be pointed at.
struct HelperOwner {
    let application: NSRunningApplication
    let pid: pid_t
}

final class ManagedWindow {
    let id: CGWindowID
    let element: AXUIElement
    /// The process that owns the `AXUIElement`: the one Accessibility is written to and the
    /// one the window server, `frontmostApplication` and the hide notifications name. For a
    /// helper's window this is the helper, not the application it stands for — see `owner`.
    let pid: pid_t
    /// Set when the window belongs to an accessory helper spawned by an ordinary application,
    /// as Steam's do. Everything that asks *which application* this window is — the float
    /// rules, the `app:` selector, the state report, a layout profile, and the quit on a last
    /// window — reads the owner; everything that talks to the window itself keeps using `pid`.
    let owner: HelperOwner?
    /// The owner's bundle identifier when there is one, else the process's own.
    let bundleID: String?
    var title: String?
    /// Where the window sat before it was stashed off-screen, so floating windows come back
    /// to exactly where they were.
    var frameBeforeStash: Box?
    var isStashed = false {
        // One place rather than at each of the three sites that bring a window back, because a
        // debt owed by a window that is on screen again is not a debt at all.
        didSet { if !isStashed { stashPending = false } }
    }
    /// The window belongs to a hidden workspace but is still where the user can see it: it was
    /// in native fullscreen when its workspace was hidden, and a fullscreen window is on a Space
    /// of its own and refuses a position. `Coordinator.settleFullscreenReturns` puts that right
    /// the moment it becomes an ordinary window again.
    var stashPending = false

    init(id: CGWindowID, element: AXUIElement, pid: pid_t, owner: HelperOwner?,
         bundleID: String?, title: String?) {
        self.id = id
        self.element = element
        self.pid = pid
        self.owner = owner
        self.bundleID = bundleID
        self.title = title
    }

    /// The application the window is a window of: the owner when it has one, and otherwise
    /// the process itself. Nil for a process LaunchServices has no record of.
    var application: NSRunningApplication? {
        owner?.application ?? NSRunningApplication(processIdentifier: pid)
    }

    /// Whether `app` is this window's application by either of the names it goes under — the
    /// process, or the owner it stands for. The callers compare against
    /// `NSWorkspace.frontmostApplication` to tell a click from an application raising a window
    /// of its own accord, and which of the two macOS reports as frontmost for a helper's window
    /// is not something to assume.
    func belongs(to app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if app.processIdentifier == pid { return true }
        guard let owner else { return false }
        return app.processIdentifier == owner.pid
            || (app.bundleIdentifier != nil && app.bundleIdentifier == owner.application.bundleIdentifier)
    }
}

protocol WindowTrackerDelegate: AnyObject {
    func windowAppeared(_ window: ManagedWindow, shouldFloat: Bool)
    func windowDisappeared(_ id: CGWindowID)
    func windowFocused(_ id: CGWindowID)
    /// The window moved or resized without toe asking — an app restoring its own remembered
    /// geometry, or the user dragging it. `resized` is which of the two Accessibility
    /// notifications this was: AppKit posts Moved when the origin changes and Resized when the
    /// size does, per frame write, so a title-bar drag is Moved only, a right- or bottom-edge
    /// drag Resized only, and a left- or top-edge drag both. That is the one fact telling a
    /// window being resized by hand from one being moved by hand, and it is not recoverable
    /// from the frame — see `DragMonitor.Kind`.
    func windowFrameChangedExternally(_ id: CGWindowID, resized: Bool)
    func screensChanged()
    /// Something moved in the window stack that toe does not manage: another application came
    /// forward, or one opened a window toe will never tile. Neither changes the layout, but
    /// both change what is stacked over the focused window.
    func windowStackChanged()
    /// The displays are showing different Spaces than they were. Nothing toe manages has
    /// moved — not the layout, and not the stacking within it — but what is in front of it
    /// all has changed, which is a different fact and deliberately a separate callback.
    func activeSpaceChanged()
}

/// Discovers windows and keeps them in sync with the running applications.
final class WindowTracker {

    weak var delegate: WindowTrackerDelegate?
    var floatRules: [FloatRule] = Config.defaultFloatRules

    private(set) var windows: [CGWindowID: ManagedWindow] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    /// The accessory helpers under observation, by their pid, and the application each one's
    /// windows belong to. Entered by `observeIfHelper` and left with `stopObserving`.
    private var owners: [pid_t: HelperOwner] = [:]
    /// Helpers found before they finished launching, each watched until it has — see
    /// `observeIfHelper`.
    private var pendingHelpers: [pid_t: NSKeyValueObservation] = [:]
    private var runningApplications: NSKeyValueObservation?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func window(_ id: CGWindowID) -> ManagedWindow? { windows[id] }

    /// The application a process's windows are windows of — the owner for a helper under
    /// observation, and the process's own record for anything else. What the state report
    /// names a window by: a Steam window is Steam's, not Steam Helper's.
    func application(of pid: pid_t) -> NSRunningApplication? {
        owners[pid]?.application ?? NSRunningApplication(processIdentifier: pid)
    }

    /// Drop a window the window server says no longer exists — a `kAXUIElementDestroyed` that
    /// never arrived. Its notifications die with the element, so there is nothing to remove;
    /// the entry just has to go, or `adopt` would go on answering "already known" for an id
    /// the window server may reuse.
    func forget(_ id: CGWindowID) {
        windows.removeValue(forKey: id)
    }

    /// The windows of `front`'s application that have gone behind a native tab: tracked, but
    /// no longer in the application's `AXWindows` list. A window on another Space stays in
    /// that list and so does a minimized one; a tab that is not selected is the one thing
    /// that leaves it (measured on Ghostty, #165). What `WorkspaceManager.tabCameForward`
    /// decides from.
    ///
    /// Free for an application with no other tracked window, which is most of the calls; for
    /// the rest it is one round trip for the list and one per window listed, on the paths
    /// that already paid six for `isManageable`. A list that could not be read at all — the
    /// application is stopped, or slow past `axMessagingTimeout` — is not an empty list: it
    /// says nothing, and nothing hidden is the answer that changes nothing.
    func hiddenTabs(of pid: pid_t, excluding front: CGWindowID) -> Set<CGWindowID> {
        let mine = Set(windows.values.lazy.filter { $0.pid == pid && $0.id != front }.map(\.id))
        guard !mine.isEmpty,
              let listed = AX.application(pid).value(kAXWindowsAttribute) as? [AXUIElement]
        else { return [] }
        return mine.subtracting(listed.compactMap(\.windowID))
    }

    /// The float rules' answer for a window, asked again for one that has come out from
    /// behind a tab and is being placed for the first time.
    func shouldFloat(_ window: ManagedWindow) -> Bool {
        floatRules.contains { $0.matches(bundleID: window.bundleID, title: window.title) }
    }

    // MARK: - Lifecycle

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appLaunched(_:)),
                              name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appTerminated(_:)),
                              name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appActivated(_:)),
                              name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Switching Spaces usually activates a different application, and the notification
        // above would have covered it — but not when the fullscreen window belongs to an
        // application that also owns tiled windows, which is the one case where nothing else
        // says the frontmost window has changed.
        workspace.addObserver(self, selector: #selector(spaceChanged),
                              name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Helpers are found from the running-applications list rather than the launch
        // notification, because the notification is not posted for them: Steam launching
        // arrives as one `didLaunchApplication` for `com.valvesoftware.steam` and nothing at
        // all for Steam Helper (measured, #158). `runningApplications` is key-value observable
        // and does change when the helper registers, so every change sweeps it. Cheap: a
        // sweep is one pass over the list, and the `sysctl` only for a name that matched.
        runningApplications = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) {
            [weak self] workspace, _ in
            self?.sweepHelpers(among: workspace.runningApplications)
        }

        let running = NSWorkspace.shared.runningApplications
        for app in running where app.activationPolicy == .regular {
            observe(app)
        }
        sweepHelpers(among: running)
    }

    @objc private func screensChanged() { delegate?.screensChanged() }

    /// Deliberately not `noteStackChange`. That one sinks unfocused floats, and a Space switch
    /// is the one moment it must not: `WindowStack.windowsAbove` returns an empty set for a
    /// window that is off screen, and `Stacking.raiseOrder` reads empty as "this float is on
    /// top of the tiles it covers" rather than "no idea" — so every switch away would raise
    /// the tiles on the Space just left. Nothing toe manages has restacked here; only what is
    /// in front of it has.
    ///
    /// Fires now and twice more shortly after, for the reason `noteStackChange` does: the
    /// frontmost application is not necessarily the new Space's yet.
    @objc private func spaceChanged() {
        delegate?.activeSpaceChanged()
        for delay in [0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.delegate?.activeSpaceChanged()
            }
        }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        observe(app)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        forgetApplication(app.processIdentifier)
    }

    private func forgetApplication(_ pid: pid_t) {
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
        if let focused = element.elementValue(kAXFocusedWindowAttribute) {
            if let id = focused.windowID, windows[id] != nil {
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
        // Main as well as focused: a native tab switch posts `kAXMainWindowChanged` and
        // nothing else — no focused-window change at all (measured on Ghostty, #165) — so
        // without it toe never hears that the window in front of a tab group is a different
        // window. An ordinary focus change posts both, and hearing it twice is harmless.
        for notification in [kAXWindowCreatedNotification,
                             kAXFocusedWindowChangedNotification,
                             kAXMainWindowChangedNotification,
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

    /// Observes every accessory that is an ordinary application's helper — Steam Helper,
    /// which owns every window Steam shows (#158). The decision is `HelperOwnership`'s, in
    /// ToeCore; what is here is finding the owner's record and the parent pid it needs.
    ///
    /// The whole list every time, in both directions: a helper that registered before the
    /// application it belongs to — the order is the application's to choose — is found on the
    /// change that brings the application, and one already under observation is skipped at
    /// the top of `observeIfHelper`.
    ///
    /// The sweep is also where a helper's going is heard. `didTerminateApplication` is not
    /// posted for one any more than `didLaunchApplication` was (measured: Steam quitting is one
    /// notification, for `com.valvesoftware.steam`), so a helper under observation that the
    /// list no longer has is let go here, as `appTerminated` lets an ordinary application go.
    private func sweepHelpers(among running: [NSRunningApplication]) {
        let alive = Set(running.map(\.processIdentifier))
        for pid in owners.keys where !alive.contains(pid) { forgetApplication(pid) }
        for pid in pendingHelpers.keys where !alive.contains(pid) { pendingHelpers.removeValue(forKey: pid) }
        let regular = Set(running.lazy.filter { $0.activationPolicy == .regular }
                                      .compactMap(\.bundleIdentifier))
        for app in running where app.activationPolicy == .accessory {
            observeIfHelper(app, regular: regular, among: running)
        }
    }

    /// The owner is found by bundle identifier and not by walking the parent pid into
    /// `NSWorkspace`: Steam's `NSRunningApplication` reports `processIdentifier == -1`, so a
    /// lookup by pid finds nothing, where the identifier finds the record that names it and
    /// quits it. The parent pid is kept as well, since it is the process Accessibility can be
    /// asked about — see `HelperOwner`.
    private func observeIfHelper(_ app: NSRunningApplication, regular: Set<String>,
                                 among running: [NSRunningApplication]) {
        let pid = app.processIdentifier
        guard pid != ownPID, observers[pid] == nil else { return }
        let parent = Processes.parentPID(of: pid)
        guard let ownerID = HelperOwnership.owner(of: app.bundleIdentifier, regular: regular,
                                                  spawnedByLaunchd: parent == nil || parent == 1),
              let parent,
              let owner = running.first(where: {
                  $0.activationPolicy == .regular && $0.bundleIdentifier == ownerID
              })
        else { return }
        // The list changes the moment the helper registers, which is before it has finished
        // launching, and an `AXObserverAddNotification` made then fails with
        // `cannotComplete` and is never retried — so Steam's window, which opens seconds later,
        // was never heard of (measured). `didLaunchApplication` would have said when, for an
        // application it is posted for; `isFinishedLaunching` is the same fact, observable.
        guard app.isFinishedLaunching else {
            guard pendingHelpers[pid] == nil else { return }
            pendingHelpers[pid] = app.observe(\.isFinishedLaunching, options: [.new]) {
                [weak self] app, _ in
                guard let self, app.isFinishedLaunching else { return }
                self.pendingHelpers.removeValue(forKey: pid)
                self.sweepHelpers(among: NSWorkspace.shared.runningApplications)
            }
            return
        }
        owners[pid] = HelperOwner(application: owner, pid: parent)
        Log.info("observing \(app.bundleIdentifier ?? "?") (pid \(pid)) as a helper of \(ownerID)")
        observe(app)
    }

    /// The run-loop source has to come off the run loop as well as out of `observers`, or
    /// every launched-and-quit application leaves one behind for the life of the session.
    private func stopObserving(_ pid: pid_t) {
        owners.removeValue(forKey: pid)
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func adoptWindows(of pid: pid_t) {
        let element = AX.application(pid)
        for window in element.windows { adopt(window, pid: pid) }
    }

    @discardableResult
    func adopt(_ element: AXUIElement, pid: pid_t) -> ManagedWindow? {
        // The window already known is answered before `isManageable` is asked, not after: that
        // is six round trips, this path runs on every focus change — twice now, since a click
        // posts a main-window change as well as a focused one — and for a window toe already
        // has, the answer would not be used. A known window that has since minimized or gone
        // fullscreen is heard about through its own notifications and `checkPresence`, not by
        // re-examining it on every click.
        if let id = element.windowID, let existing = windows[id] { return existing }
        guard isManageable(element) else { return nil }
        guard let id = element.windowID else { return nil }

        let owner = owners[pid]
        let app = owner?.application ?? NSRunningApplication(processIdentifier: pid)
        let window = ManagedWindow(id: id, element: element, pid: pid, owner: owner,
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

        delegate?.windowAppeared(window, shouldFloat: shouldFloat(window))
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
            delegate?.windowFrameChangedExternally(id, resized: notification == kAXWindowResizedNotification)

        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            guard let id = windows.first(where: { CFEqual($0.value.element, element) })?.key else { return }
            windows.removeValue(forKey: id)
            delegate?.windowDisappeared(id)

        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            let window = adopt(element, pid: element.pid)
            if let id = window?.id ?? element.windowID, windows[id] != nil {
                delegate?.windowFocused(id)
            }

        case kAXApplicationActivatedNotification:
            let app = AX.application(element.pid)
            if let focusedElement = app.elementValue(kAXFocusedWindowAttribute) {
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

enum Processes {
    /// The parent of `pid`, or nil for a process the kernel no longer has — one that quit
    /// between the launch notification and now. `KERN_PROC_PID` is the one lookup that answers
    /// for a process toe does not own and did not spawn.
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}

private func axCallback(observer: AXObserver, element: AXUIElement,
                        notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    tracker.handle(notification: notification as String, element: element)
}
