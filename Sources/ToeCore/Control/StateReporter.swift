import Foundation

/// The four facts about a live window the reporter reads.
///
/// `ManagedWindow` is the app layer's: it holds the `AXUIElement` and the stash bookkeeping, and
/// neither can cross into ToeCore. The report needs none of that — an id to key on, a pid to
/// name the application by, and the two strings — so this is the shape that crosses the target
/// boundary, and the shape a selftest builds by hand.
public struct TrackedWindow: Equatable, Sendable {
    public var id: WindowID
    public var pid: pid_t
    public var bundleID: String?
    public var title: String?

    public init(id: WindowID, pid: pid_t, bundleID: String? = nil, title: String? = nil) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
    }
}

/// Turns what toe knows into what `toe query` answers with.
///
/// A free function over the pieces rather than a method on `Coordinator`, so that the assembly
/// — which is nearly all of it — is separable from the hub that owns the state. It reads and
/// writes nothing: `render()` is asked for the frames, exactly as `apply` asks for them, and
/// every other field is already in memory.
///
/// **No Accessibility calls, on purpose.** The obvious way to report where a window is would be
/// to ask the system, and that is a synchronous round trip per window on the main thread —
/// twenty windows is twenty chances to block the compositor for the messaging timeout, in answer
/// to a question nobody urgent asked. It would also be wrong: a window on a hidden workspace is
/// parked in the stash corner, and the stash corner is where toe put it rather than where it
/// belongs. The frame the layout intends is the true answer to "where is this window", and it is
/// free.
///
/// The two names that *do* come from the system — what an application calls itself, and what a
/// display is called — arrive as lookups, the way `monitorKey` already did, so that everything
/// this function decides (`hidden`, a `frame` that is nil while stashed, the tiles-then-floats
/// order a layout profile replays) is decided here, where the selftest can reach it.
public enum StateReporter {

    /// - Parameters:
    ///   - tracked: every window toe has hold of, in any order; the report is sorted by id.
    ///   - monitorKey: the session file's durable name for a display, or nil for one it cannot name.
    ///   - appName: what a person calls the process — `NSRunningApplication.localizedName` in the
    ///     app layer. Nil or empty falls back to the bundle identifier, and then to the pid.
    ///   - screenName: the display's own name — `NSScreen.localizedName` — or nil.
    ///   - bar: whether the bar is on screen, which the Coordinator knows and the layout does not.
    public static func report(_ workspaces: WorkspaceManager,
                              tracked: [TrackedWindow],
                              monitorKey: (UInt32) -> String?,
                              appName: (pid_t) -> String?,
                              screenName: (UInt32) -> String?,
                              version: String?,
                              bar: BarState = .off) -> StateReport {
        let plan = workspaces.render()
        let focused = workspaces.focusedWindow

        var windows: [WindowReport] = []
        for window in tracked.sorted(by: { $0.id < $1.id }) {
            let id = window.id
            // A suspended window is reported on the workspace it will go back to, and hidden:
            // it is on a Space the user is not looking at, which to a reader is the same fact a
            // stashed window's `hidden` states — toe has it, and it is not on screen. A window
            // behind a native tab is the same again, on the workspace of the tab in front of it.
            let suspension = workspaces.suspended[id]
            let front = workspaces.tabs.front(of: id)
            let index = workspaces.workspaceIndex(of: id) ?? suspension?.workspace
                ?? front.flatMap { workspaces.workspaceIndex(of: $0) }
            windows.append(WindowReport(
                id: id,
                app: name(of: window, appName: appName),
                bundle: window.bundleID,
                title: window.title,
                workspace: index,
                monitor: index.flatMap { workspaces.workspaces[$0]?.monitorID },
                frame: plan.frames[id] ?? plan.floating[id],
                floating: workspaces.isFloating(id),
                focused: id == focused,
                hidden: plan.stashed.contains(id) || suspension != nil || front != nil))
        }

        let visible = workspaces.visibleWorkspaceIndices
        var rows: [WorkspaceReport] = []
        for index in workspaces.workspaces.keys.sorted() {
            guard let ws = workspaces.workspaces[index] else { continue }
            rows.append(WorkspaceReport(
                index: index,
                monitor: ws.monitorID,
                visible: visible.contains(index),
                focused: index == workspaces.focusedWorkspaceIndex,
                // Tiles in tree order, then the detached windows. This is the order a layout
                // profile replays, and replaying it is what reproduces the shape — so it is the
                // order reported, rather than anything sorted for tidiness.
                windows: ws.layout.windowIDs + ws.floating.sorted()))
        }

        let monitors = workspaces.monitors.map { monitor in
            MonitorReport(id: monitor.id,
                          key: monitorKey(monitor.id),
                          name: screenName(monitor.id),
                          frame: monitor.frame,
                          usable: monitor.usable,
                          workspace: workspaces.activeWorkspace[monitor.id],
                          focused: monitor.id == workspaces.focusedMonitorID)
        }

        return StateReport(version: version,
                           bar: bar,
                           focusedWindow: focused,
                           focusedWorkspace: workspaces.focusedWorkspaceIndex,
                           focusedMonitor: workspaces.focusedMonitorID,
                           monitors: monitors,
                           workspaces: rows,
                           windows: windows)
    }

    /// What a person calls the application. The bundle identifier is reported beside it and is
    /// the stabler name, but nobody asks for "the com.mitchellh.ghostty window".
    ///
    /// The empty-string check is here rather than in the lookup, so that a lookup answering
    /// `""` is treated the same as one answering nil: an `app` of `""` is a name nothing can
    /// select by, where the bundle identifier beside it is.
    private static func name(of window: TrackedWindow, appName: (pid_t) -> String?) -> String {
        if let name = appName(window.pid), !name.isEmpty { return name }
        return window.bundleID ?? "pid \(window.pid)"
    }
}
