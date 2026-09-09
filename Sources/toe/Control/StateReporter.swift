import AppKit
import ToeCore

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
enum StateReporter {

    static func report(_ workspaces: WorkspaceManager,
                       tracked: [WindowID: ManagedWindow],
                       monitorKey: (UInt32) -> String?,
                       version: String?) -> StateReport {
        let plan = workspaces.render()
        let focused = workspaces.focusedWindow

        var windows: [WindowReport] = []
        for id in tracked.keys.sorted() {
            guard let window = tracked[id] else { continue }
            let index = workspaces.workspaceIndex(of: id)
            windows.append(WindowReport(
                id: id,
                app: name(of: window),
                bundle: window.bundleID,
                title: window.title,
                workspace: index,
                monitor: index.flatMap { workspaces.workspaces[$0]?.monitorID },
                frame: plan.frames[id] ?? plan.floating[id],
                floating: workspaces.isFloating(id),
                focused: id == focused,
                hidden: plan.stashed.contains(id)))
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

        let screens = Dictionary(NSScreen.screens.map { ($0.displayID, $0.localizedName) },
                                 uniquingKeysWith: { first, _ in first })
        let monitors = workspaces.monitors.map { monitor in
            MonitorReport(id: monitor.id,
                          key: monitorKey(monitor.id),
                          name: screens[monitor.id],
                          frame: monitor.frame,
                          usable: monitor.usable,
                          workspace: workspaces.activeWorkspace[monitor.id],
                          focused: monitor.id == workspaces.focusedMonitorID)
        }

        return StateReport(version: version,
                           focusedWindow: focused,
                           focusedWorkspace: workspaces.focusedWorkspaceIndex,
                           focusedMonitor: workspaces.focusedMonitorID,
                           monitors: monitors,
                           workspaces: rows,
                           windows: windows)
    }

    /// What a person calls the application. The bundle identifier is reported beside it and is
    /// the stabler name, but nobody asks for "the com.mitchellh.ghostty window".
    private static func name(of window: ManagedWindow) -> String {
        if let running = NSRunningApplication(processIdentifier: window.pid),
           let name = running.localizedName, !name.isEmpty {
            return name
        }
        return window.bundleID ?? "pid \(window.pid)"
    }
}
