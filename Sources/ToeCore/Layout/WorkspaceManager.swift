import Foundation

/// What the app layer should do to the screen after a state change.
public struct RenderPlan: Equatable {
    /// Tiled windows on a visible workspace and the frame each should occupy (gaps applied).
    public var frames: [WindowID: Box] = [:]
    /// Floating windows on a visible workspace and the frame each should occupy. Unlike
    /// `frames`, the app layer writes these once when they change and never re-asserts them —
    /// a floating window belongs to whoever is dragging it.
    public var floating: [WindowID: Box] = [:]
    /// Windows on a hidden workspace. The app layer parks these off-screen.
    public var stashed: Set<WindowID> = []
    /// The window that should hold focus, if it changed.
    public var focus: WindowID?

    public init() {}
}

public final class Workspace {
    public let index: Int              // 1...10
    public var monitorID: UInt32
    public var layout: DwindleLayout
    public var floating: Set<WindowID> = []

    init(index: Int, monitorID: UInt32, area: Box, options: DwindleOptions) {
        self.index = index
        self.monitorID = monitorID
        self.layout = DwindleLayout(area: area, options: options)
    }

    public var windows: Set<WindowID> {
        Set(layout.windowIDs).union(floating)
    }

    public var isEmpty: Bool { layout.isEmpty && floating.isEmpty }
}

/// Owns every workspace and the monitor each is bound to.
///
/// Mirrors Hyprland: each monitor has its own active workspace, a workspace lives on exactly
/// one monitor, and switching to a workspace that lives elsewhere moves focus to that monitor.
public final class WorkspaceManager {

    public static let workspaceCount = 10

    public private(set) var monitors: [Monitor] = []
    public private(set) var workspaces: [Int: Workspace] = [:]
    /// monitor id -> active workspace index
    public private(set) var activeWorkspace: [UInt32: Int] = [:]
    public private(set) var focusedMonitorID: UInt32 = 0
    /// Most-recent-first. Drives the directional-focus tie-break and workspace re-focus.
    public private(set) var focusHistory: [WindowID] = []
    /// Previous workspace on the focused monitor, for `workspace previous`.
    private var previousWorkspace: [UInt32: Int] = [:]
    /// Frames of floating windows, supplied by the app layer so directional search has an
    /// origin box for them.
    public var floatingFrames: [WindowID: Box] = [:]
    /// The pointer, in AX coordinates, supplied by the app layer so ToeCore stays free of
    /// AppKit. Hyprland splits the window under the cursor when there is no focused tiled
    /// window to split — see `onWindowCreatedTiling`'s `use_active_for_splits` branch.
    public var cursorLocation: (() -> Point?)?

    public var options: DwindleOptions {
        didSet { workspaces.values.forEach { $0.layout.options = options; $0.layout.recalculate() } }
    }
    public var gaps: Gaps

    public init(options: DwindleOptions = DwindleOptions(), gaps: Gaps = Gaps()) {
        self.options = options
        self.gaps = gaps
    }

    // MARK: - Monitors

    public func setMonitors(_ newMonitors: [Monitor]) {
        precondition(!newMonitors.isEmpty, "at least one monitor is required")
        monitors = newMonitors
        let ids = Set(newMonitors.map(\.id))

        if !ids.contains(focusedMonitorID) {
            focusedMonitorID = newMonitors[0].id
        }

        // Re-home workspaces whose monitor disappeared.
        for ws in workspaces.values where !ids.contains(ws.monitorID) {
            ws.monitorID = focusedMonitorID
        }
        activeWorkspace = activeWorkspace.filter { ids.contains($0.key) }

        // Every monitor needs an active workspace.
        for monitor in newMonitors where activeWorkspace[monitor.id] == nil {
            activeWorkspace[monitor.id] = firstFreeWorkspaceIndex()
        }

        for monitor in newMonitors {
            for ws in workspaces.values where ws.monitorID == monitor.id {
                ws.layout.area = monitor.usable
                ws.layout.recalculate()
            }
        }
    }

    public func monitor(id: UInt32) -> Monitor? { monitors.first { $0.id == id } }
    public var focusedMonitor: Monitor? { monitor(id: focusedMonitorID) }

    /// The lowest workspace not already shown on another monitor.
    private func firstFreeWorkspaceIndex() -> Int {
        let taken = Set(activeWorkspace.values)
        return (1...Self.workspaceCount).first { !taken.contains($0) } ?? 1
    }

    // MARK: - Workspaces

    @discardableResult
    public func workspace(_ index: Int, onMonitor monitorID: UInt32? = nil) -> Workspace {
        if let existing = workspaces[index] { return existing }
        let mid = monitorID ?? focusedMonitorID
        let area = monitor(id: mid)?.usable ?? Box(x: 0, y: 0, w: 0, h: 0)
        let ws = Workspace(index: index, monitorID: mid, area: area, options: options)
        workspaces[index] = ws
        return ws
    }

    public var focusedWorkspaceIndex: Int { activeWorkspace[focusedMonitorID] ?? 1 }
    public var focusedWorkspace: Workspace { workspace(focusedWorkspaceIndex) }

    /// Every workspace currently shown on some monitor.
    public var visibleWorkspaceIndices: Set<Int> { Set(activeWorkspace.values) }

    public func workspaceIndex(of id: WindowID) -> Int? {
        workspaces.first { $0.value.windows.contains(id) }?.key
    }

    public var focusedWindow: WindowID? {
        let visible = visibleWindows()
        return focusHistory.first { visible.contains($0) }
    }

    public func visibleWindows() -> Set<WindowID> {
        var out: Set<WindowID> = []
        for index in visibleWorkspaceIndices {
            if let ws = workspaces[index] { out.formUnion(ws.windows) }
        }
        return out
    }

    // MARK: - Window lifecycle

    /// Hyprland looks at exactly one window — `m_lastWindow` — and falls to the pointer when
    /// it is floating, unmapped or on another workspace. `focusHistory.first` is that window.
    private func anchor(on ws: Workspace, excluding id: WindowID? = nil) -> WindowID? {
        guard let last = focusHistory.first, last != id, ws.layout.contains(last) else { return nil }
        return last
    }

    /// The pointer, but only while it is on the workspace's own monitor — Hyprland's
    /// `vectorToWindowUnified` / `isPointOnReservedArea` are both scoped to that monitor.
    private func focalPoint(on ws: Workspace) -> Point? {
        guard let point = cursorLocation?(),
              let monitor = monitor(id: ws.monitorID),
              monitor.frame.contains(point)
        else { return nil }
        return point
    }

    /// Add a window to the active workspace of the focused monitor, splitting the focused
    /// window (Hyprland's `use_active_for_splits`, which Omarchy leaves at its default).
    public func addWindow(_ id: WindowID, floating: Bool = false, toWorkspace index: Int? = nil) {
        let target = index ?? focusedWorkspaceIndex
        let ws = workspace(target)
        guard !ws.windows.contains(id) else { return }

        if floating {
            ws.floating.insert(id)
        } else {
            ws.layout.insert(id, anchor: anchor(on: ws, excluding: id), focalPoint: focalPoint(on: ws))
        }
        noteFocus(id)
    }

    public func removeWindow(_ id: WindowID) {
        for ws in workspaces.values {
            ws.layout.remove(id)
            ws.floating.remove(id)
        }
        focusHistory.removeAll { $0 == id }
    }

    /// Toggle a window between the dwindle tree and floating.
    public func toggleFloating(_ id: WindowID) {
        guard let index = workspaceIndex(of: id) else { return }
        let ws = workspace(index)
        if ws.floating.contains(id) {
            ws.floating.remove(id)
            ws.layout.insert(id, anchor: anchor(on: ws, excluding: id), focalPoint: focalPoint(on: ws))
        } else {
            ws.layout.remove(id)
            ws.floating.insert(id)
        }
    }

    public func isFloating(_ id: WindowID) -> Bool {
        guard let index = workspaceIndex(of: id) else { return false }
        return workspaces[index]?.floating.contains(id) ?? false
    }

    public func noteFocus(_ id: WindowID) {
        focusHistory.removeAll { $0 == id }
        focusHistory.insert(id, at: 0)
        if let index = workspaceIndex(of: id), let ws = workspaces[index] {
            focusedMonitorID = ws.monitorID
        }
    }

    // MARK: - Commands

    /// `movefocus <dir>` — returns the window that should receive focus.
    public func windowInDirection(_ dir: Direction, from id: WindowID? = nil) -> WindowID? {
        guard let source = id ?? focusedWindow,
              let index = workspaceIndex(of: source),
              let ws = workspaces[index],
              let origin = ws.layout.idealBox(of: source) ?? floatingFrames[source]
        else { return nil }

        // Candidates: every window on a *visible* workspace, floating ones included — a
        // floated window you cannot focus again is a window you have lost. Hyprland's
        // `window_direction_monitor_fallback` defaults to true, so focus crosses monitors.
        var candidates: [(id: WindowID, box: Box)] = []
        for wsIndex in visibleWorkspaceIndices {
            guard let w = workspaces[wsIndex] else { continue }
            candidates.append(contentsOf: w.layout.idealBoxes())
            for id in w.floating {
                if let box = floatingFrames[id] { candidates.append((id: id, box: box)) }
            }
        }

        return DirectionalSearch.windowInDirection(
            from: origin,
            ignoring: source,
            candidates: candidates,
            direction: dir,
            focusHistory: focusHistory
        )
    }

    /// `swapwindow <dir>` — exchange the focused window with its neighbour, leaving the
    /// tree shape untouched. Returns true if anything moved.
    @discardableResult
    public func swapWindow(_ dir: Direction) -> Bool {
        guard let source = focusedWindow,
              let target = windowInDirection(dir, from: source),
              let sourceIndex = workspaceIndex(of: source),
              let targetIndex = workspaceIndex(of: target)
        else { return false }

        guard let a = workspaces[sourceIndex], let b = workspaces[targetIndex] else { return false }
        // Across monitors too, only the payloads move: `switchWindows` swaps the windows'
        // monitor/workspace pointers rather than re-inserting, so both trees keep their shape.
        DwindleLayout.swap(source, in: a.layout, with: target, in: b.layout)
        return true
    }

    /// `movewindow <dir>` — reparent the focused window towards a direction.
    @discardableResult
    public func moveWindow(_ dir: Direction) -> Bool {
        guard let source = focusedWindow,
              let index = workspaceIndex(of: source),
              let ws = workspaces[index],
              ws.layout.contains(source)
        else { return false }
        ws.layout.moveWindow(source, dir)
        return true
    }

    /// `workspace <n>`. If the target workspace lives on another monitor, focus follows it
    /// there, exactly as Hyprland does.
    public func switchTo(workspace index: Int) {
        guard (1...Self.workspaceCount).contains(index) else { return }

        if let owner = activeWorkspace.first(where: { $0.value == index })?.key {
            focusedMonitorID = owner
            refocusVisible()
            return
        }

        let ws = workspaces[index]
        let targetMonitor: UInt32
        if let ws, !ws.isEmpty, monitor(id: ws.monitorID) != nil {
            targetMonitor = ws.monitorID           // follow the workspace to its monitor
        } else {
            targetMonitor = focusedMonitorID       // empty workspace re-homes to us
        }

        previousWorkspace[targetMonitor] = activeWorkspace[targetMonitor]
        let target = workspace(index, onMonitor: targetMonitor)
        target.monitorID = targetMonitor
        if let m = monitor(id: targetMonitor) {
            target.layout.area = m.usable
            target.layout.recalculate()
        }
        activeWorkspace[targetMonitor] = index
        focusedMonitorID = targetMonitor
        refocusVisible()
    }

    public func switchToPreviousWorkspace() {
        if let prev = previousWorkspace[focusedMonitorID] { switchTo(workspace: prev) }
    }

    public func switchToRelativeWorkspace(_ delta: Int) {
        let current = focusedWorkspaceIndex
        var next = (current - 1 + delta) % Self.workspaceCount
        if next < 0 { next += Self.workspaceCount }
        switchTo(workspace: next + 1)
    }

    /// `movetoworkspace <n>` / `movetoworkspacesilent <n>`.
    public func moveFocusedWindow(toWorkspace index: Int, follow: Bool) {
        guard (1...Self.workspaceCount).contains(index),
              let id = focusedWindow,
              let currentIndex = workspaceIndex(of: id),
              currentIndex != index
        else { return }

        let wasFloating = isFloating(id)
        workspaces[currentIndex]?.layout.remove(id)
        workspaces[currentIndex]?.floating.remove(id)

        let target = workspace(index)
        if wasFloating {
            target.floating.insert(id)
        } else {
            target.layout.insert(id, anchor: anchor(on: target, excluding: id),
                                 focalPoint: focalPoint(on: target))
        }

        if follow {
            switchTo(workspace: index)
            noteFocus(id)
        }
    }

    private func refocusVisible() {
        // Focus the most recently used window that is now visible.
        let visible = visibleWindows()
        if let next = focusHistory.first(where: { visible.contains($0) }) {
            noteFocusWithoutMonitorChange(next)
        }
    }

    private func noteFocusWithoutMonitorChange(_ id: WindowID) {
        focusHistory.removeAll { $0 == id }
        focusHistory.insert(id, at: 0)
    }

    // MARK: - Rendering

    /// Where a floating window belongs. Hyprland restores `m_vLastFloatingSize` and
    /// `m_vLastFloatingPosition`; `floatingFrames` is that, kept current by the app layer as
    /// the window is dragged. A frame that no longer touches the monitor at all — remembered
    /// from a display that has since been unplugged — is pulled back in rather than leaving
    /// the window stranded off-screen. Anything that still overlaps is left exactly alone, so
    /// dragging a window half off an edge is not undone on the next render.
    private func floatingBox(for id: WindowID, on monitor: Monitor) -> Box {
        let usable = monitor.usable
        guard let remembered = floatingFrames[id] else {
            let w = usable.w / 2.0, h = usable.h / 2.0
            return Box(x: usable.minX + (usable.w - w) / 2.0,
                       y: usable.minY + (usable.h - h) / 2.0,
                       w: w, h: h).rounded()
        }
        if remembered.intersects(usable) { return remembered }

        let w = min(remembered.w, usable.w)
        let h = min(remembered.h, usable.h)
        return Box(x: clampf(remembered.x, usable.minX, max(usable.minX, usable.maxX - w)),
                   y: clampf(remembered.y, usable.minY, max(usable.minY, usable.maxY - h)),
                   w: w, h: h).rounded()
    }

    public func render() -> RenderPlan {
        var plan = RenderPlan()
        let visibleIndices = visibleWorkspaceIndices

        for (index, ws) in workspaces {
            if visibleIndices.contains(index) {
                if let m = monitor(id: ws.monitorID), ws.layout.area != m.usable {
                    ws.layout.area = m.usable
                    ws.layout.recalculate()
                }
                for (id, box) in ws.layout.frames(gaps: gaps) { plan.frames[id] = box }
                if let m = monitor(id: ws.monitorID) {
                    for id in ws.floating { plan.floating[id] = floatingBox(for: id, on: m) }
                }
            } else {
                plan.stashed.formUnion(ws.windows)
            }
        }

        plan.focus = focusedWindow
        return plan
    }
}

public extension WorkspaceManager {

    /// The windows on a workspace in a stable, meaningful order: tiled windows in tree order
    /// (left to right, top to bottom), then floating ones.
    func orderedWindows(inWorkspace index: Int) -> [WindowID] {
        guard let ws = workspaces[index] else { return [] }
        return ws.layout.windowIDs + ws.floating.sorted()
    }

    /// Which monitor, if any, is currently showing this workspace.
    func monitorShowing(workspace index: Int) -> UInt32? {
        activeWorkspace.first { $0.value == index }?.key
    }
}

/// Collapses a window list into one entry per application, preserving the order the
/// applications first appear in.
public enum AppGrouping {

    public struct Group: Equatable {
        public let name: String
        public let windows: [WindowID]
        public var count: Int { windows.count }
    }

    public static func group(_ windows: [WindowID], name: (WindowID) -> String?) -> [Group] {
        var order: [String] = []
        var byName: [String: [WindowID]] = [:]

        for window in windows {
            guard let appName = name(window) else { continue }
            if byName[appName] == nil { order.append(appName) }
            byName[appName, default: []].append(window)
        }
        return order.map { Group(name: $0, windows: byName[$0] ?? []) }
    }
}
