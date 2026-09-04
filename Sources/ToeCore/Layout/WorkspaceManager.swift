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
    /// Frames of floating windows, kept current by the app layer so a float stays where the
    /// user last put it — what `floatingBox` renders, and what the session file remembers.
    public var floatingFrames: [WindowID: Box] = [:]
    /// Where each window is on `togglefloating`'s cycle: 1 is the first floating size, 2 the
    /// larger one, and a window with no entry is either tiled or floating because the app
    /// layer adopted it that way — the next press tiles that one rather than resizing a
    /// window toe never sized itself.
    public private(set) var floatingStage: [WindowID: Int] = [:]
    /// The pointer, in AX coordinates, supplied by the app layer so ToeCore stays free of
    /// AppKit. Hyprland splits the window under the cursor when there is no focused tiled
    /// window to split — see `onWindowCreatedTiling`'s `use_active_for_splits` branch.
    public var cursorLocation: (() -> Point?)?

    public var options: DwindleOptions {
        didSet { workspaces.values.forEach { $0.layout.options = options; $0.layout.recalculate() } }
    }
    public var gaps: Gaps
    /// How big a window is when it leaves the tree. See `centredFloatingBox`.
    public var floatingSize = FloatingSize()

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

    /// The window every command acts on: the most recently focused window on the workspace the
    /// focused monitor is showing.
    ///
    /// That workspace and not every visible one. `visibleWindows()` is the union across every
    /// monitor, and on two displays it therefore held the other display's windows too — so
    /// bringing an empty workspace up on one monitor handed the focus to whichever window on
    /// the *other* was most recently used, and `movefocus`, `swapwindow`, `movetoworkspace` and
    /// `killactive` all worked from there. On one display the two sets are the same set, which
    /// is why this went unnoticed.
    ///
    /// An empty workspace therefore has no focused window and those commands do nothing on it,
    /// which is what Hyprland does: `workspace` moves the focus to the monitor, and an empty
    /// workspace has no window to give it to. It is also what one display already did.
    public var focusedWindow: WindowID? {
        let mine = focusedWorkspace.windows
        return focusHistory.first { mine.contains($0) }
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
        floatingStage.removeValue(forKey: id)
        focusHistory.removeAll { $0 == id }
    }

    /// Walk a window one step around `togglefloating`'s cycle: tiled, floating at the first
    /// size, floating at the larger one, tiled again.
    ///
    /// A window the app layer floated on its own — a dialog, anything that will not take a
    /// size — has no stage, and the first press tiles it. Resizing a window that arrived at a
    /// size of its own choosing would be toe overriding a decision it never made.
    public func toggleFloating(_ id: WindowID) {
        guard let index = workspaceIndex(of: id) else { return }
        let ws = workspace(index)
        let next = ws.floating.contains(id) ? (floatingStage[id] ?? FloatingSize.stages) + 1 : 1

        guard next <= FloatingSize.stages else {
            ws.floating.remove(id)
            floatingStage.removeValue(forKey: id)
            ws.layout.insert(id, anchor: anchor(on: ws, excluding: id), focalPoint: focalPoint(on: ws))
            return
        }

        ws.layout.remove(id)
        ws.floating.insert(id)
        floatingStage[id] = next
        // A window leaving the tree, or growing to the next size, is centred. This is set here
        // rather than derived in `floatingBox` so that it happens once, on the keypress —
        // deriving it every render would drag the window back to the middle of the screen the
        // moment you tried to move it.
        if let m = monitor(id: ws.monitorID) {
            floatingFrames[id] = centredFloatingBox(on: m, stage: next)
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
    ///
    /// Two different searches, because a workspace holds two different kinds of window.
    ///
    /// Tiles are laid out in space, and the walk between them is Hyprland's exactly: edge
    /// adjacency, most recently focused breaking a tie, crossing monitors.
    ///
    /// Detached windows are not in that space at all. `togglefloating` centres every one of
    /// them, so two of a size land exactly on top of each other and no arrow can mean "the one
    /// underneath this one" — geometry has nothing left to say about them. They are a list
    /// instead, in a stable order, walked forward and back, which is reversible by
    /// construction: whatever a direction does, its opposite undoes.
    ///
    /// The two meet at the edge of the grid. A direction with no tile that way lands in the
    /// list, at whichever end it arrives from, and walking off either end of the list returns
    /// to the tile the focus came from — so holding down one arrow goes round tile, list,
    /// tile, and every direction behaves the same way.
    public func windowInDirection(_ dir: Direction, from id: WindowID? = nil) -> WindowID? {
        guard let source = id ?? focusedWindow,
              let index = workspaceIndex(of: source),
              let ws = workspaces[index]
        else { return nil }

        if ws.floating.contains(source) { return stepThroughDetached(on: ws, from: source, dir) }

        guard let origin = ws.layout.idealBox(of: source) else { return nil }

        // Every tile on a *visible* workspace, and only tiles: Hyprland's
        // `window_direction_monitor_fallback` defaults to true, so the walk crosses monitors.
        var candidates: [(id: WindowID, box: Box)] = []
        for wsIndex in visibleWorkspaceIndices {
            guard let w = workspaces[wsIndex] else { continue }
            candidates.append(contentsOf: w.layout.idealBoxes())
        }

        if let onTheGrid = DirectionalSearch.windowInDirection(
            from: origin,
            ignoring: source,
            candidates: candidates,
            direction: dir,
            focusHistory: focusHistory
        ) { return onTheGrid }

        // Nothing that way on the grid. What lies past its edge is this workspace's detached
        // windows: one you cannot reach with the keyboard is one you have lost.
        let detached = detachedList(on: ws)
        return dir.isForward ? detached.first : detached.last
    }

    /// The workspace's detached windows, in a stable order.
    ///
    /// By window id, which is the order they were opened in. It needs no bookkeeping of its
    /// own, it survives a restart — the session file already sorts them the same way — and a
    /// window keeps its place in it when another is floated or tiled. A list that reshuffled
    /// under the focus would be no better than the geometry it replaces.
    private func detachedList(on ws: Workspace) -> [WindowID] { ws.floating.sorted() }

    /// One step along that list.
    ///
    /// Off either end is the way back to the tiles, rather than the dead stop the edge of the
    /// grid is: a list hanging off one tile has no far side to be stranded on, and stopping
    /// there made the two directions behave differently for no reason the user could see.
    private func stepThroughDetached(on ws: Workspace,
                                     from source: WindowID,
                                     _ dir: Direction) -> WindowID? {
        let list = detachedList(on: ws)
        guard let here = list.firstIndex(of: source) else { return nil }
        let next = dir.isForward ? here + 1 : here - 1
        guard list.indices.contains(next) else { return tileToComeBackTo(on: ws) }
        return list[next]
    }

    /// Where leaving the list puts the focus: the tile it came in from. With nothing in the
    /// history to go back to — a workspace whose tiles have never held the focus — the first
    /// tile on it, rather than nowhere.
    private func tileToComeBackTo(on ws: Workspace) -> WindowID? {
        focusHistory.first { ws.layout.contains($0) } ?? ws.layout.windowIDs.first
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

    /// The workspace currently shown on the monitor holding `point`. Scoped to the monitor's
    /// whole frame rather than its usable area, the way `focalPoint(on:)` is.
    private func visibleWorkspace(at point: Point) -> Workspace? {
        guard let monitor = monitors.first(where: { $0.frame.contains(point) }),
              let index = activeWorkspace[monitor.id]
        else { return nil }
        return workspaces[index]
    }

    /// The tiled branch of `IHyprLayout::onMouseMove`: a window dragged by hand trades places
    /// with whichever tile the pointer is over. That is Hyprland's `switchWindows` — the same
    /// primitive `swapwindow` uses, so the tree shape never changes — and it crosses monitors,
    /// because a tile on another display is just another leaf under the pointer.
    ///
    /// A stream of pointer moves needs no throttling: `swap` exchanges node payloads, so the
    /// node under the pointer ends up holding the dragged window itself and every further move
    /// inside it is a no-op. The next swap waits for the pointer to enter a different tile.
    ///
    /// Only tiled leaves are targets. Dragging over a floating window swaps with the tile
    /// underneath it.
    @discardableResult
    public func swapWithWindow(at point: Point, dragging source: WindowID) -> Bool {
        guard let sourceIndex = workspaceIndex(of: source),
              let sourceWorkspace = workspaces[sourceIndex],
              sourceWorkspace.layout.contains(source),
              let targetWorkspace = visibleWorkspace(at: point),
              let target = targetWorkspace.layout.node(at: point)?.window,
              target != source
        else { return false }

        DwindleLayout.swap(source, in: sourceWorkspace.layout,
                           with: target, in: targetWorkspace.layout)
        // Dragged onto another display, focus goes with the window.
        if targetWorkspace !== sourceWorkspace { noteFocus(source) }
        return true
    }

    /// `resizeactive`, and the settling of a mouse resize. A tiled window moves its splits; a
    /// floating one grows or shrinks in place, which is what Hyprland's `resizeActiveWindow`
    /// does for a window with no node — the delta goes onto its real size, top-left corner
    /// staying put. Returns true if anything changed, so the caller can skip the render.
    ///
    /// The float branch is the keyboard's: a mouse resize of a float is already the user's own
    /// business, and the coordinator never brings one here.
    @discardableResult
    public func resizeWindow(_ id: WindowID, dx: Double, dy: Double, edges: ResizeEdges = []) -> Bool {
        guard let index = workspaceIndex(of: id), let ws = workspaces[index] else { return false }
        if ws.layout.contains(id) {
            return ws.layout.resizeActive(id, dx: dx, dy: dy, edges: edges)
        }
        return growFloat(id, on: ws, dx: dx, dy: dy)
    }

    /// `growactive`: the same, with the sign relative to the window rather than to the split.
    /// For a float the two are one thing — it has no split, and the delta is already its size.
    @discardableResult
    public func growWindow(_ id: WindowID, dx: Double, dy: Double) -> Bool {
        guard let index = workspaceIndex(of: id), let ws = workspaces[index] else { return false }
        if ws.layout.contains(id) {
            return ws.layout.growActive(id, dx: dx, dy: dy)
        }
        return growFloat(id, on: ws, dx: dx, dy: dy)
    }

    private func growFloat(_ id: WindowID, on ws: Workspace, dx: Double, dy: Double) -> Bool {
        // A float that has not been rendered yet has no frame of its own; grow the one it is
        // about to get, which is the frame the user is looking at.
        guard ws.floating.contains(id), let m = monitor(id: ws.monitorID) else { return false }
        var frame = floatingFrames[id] ?? floatingBox(for: id, on: m)
        frame.w = max(Self.minimumFloatingSide, frame.w + dx)
        frame.h = max(Self.minimumFloatingSide, frame.h + dy)
        floatingFrames[id] = frame
        return true
    }

    /// Small enough that a run of `resizeactive` cannot shrink a float out of reach of the
    /// mouse, and no larger — an app with a bigger minimum will hold its own line.
    private static let minimumFloatingSide = 100.0

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

    /// `workspace e+1` / `e-1`. Cycles through the workspaces in use — the ones with windows
    /// on them, plus whatever the monitors are showing — rather than all ten, so a press never
    /// lands on a blank slot you would have to press past. With nothing else in use it does
    /// nothing, and the workspace you are on always counts as one of them.
    public func switchToRelativeWorkspace(_ delta: Int) {
        let current = focusedWorkspaceIndex
        let ring = (1...Self.workspaceCount).filter { $0 == current || inUse(workspace: $0) }
        guard ring.count > 1, let position = ring.firstIndex(of: current) else { return }
        var next = (position + delta) % ring.count
        if next < 0 { next += ring.count }
        switchTo(workspace: ring[next])
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

    /// Focus the most recently used window on the workspace `focusedMonitorID` is now showing.
    ///
    /// Scoped to that workspace, not to everything visible: `visibleWindows()` spans every
    /// monitor, and the window you are standing on is by definition the head of the history and
    /// still visible on its own display — so an unscoped scan re-selected the window it was
    /// supposed to be moving away from, and `workspace <n>` aimed at the other display moved
    /// the strip's marker and nothing else. On an empty workspace this finds nothing and leaves
    /// the history alone; `focusedWindow` then answers nil, and the coordinator focuses nothing.
    private func refocusVisible() {
        let mine = focusedWorkspace.windows
        if let next = focusHistory.first(where: { mine.contains($0) }) {
            noteFocusWithoutMonitorChange(next)
        }
    }

    private func noteFocusWithoutMonitorChange(_ id: WindowID) {
        focusHistory.removeAll { $0 == id }
        focusHistory.insert(id, at: 0)
    }

    // MARK: - Rendering

    /// How much of a floating window has to be on its monitor for its remembered frame to be
    /// taken at face value. Matches the 60pt floor the tracker uses to decide a window is a
    /// real window at all.
    private static let minimumOnScreen = 60.0

    /// Where a floating window belongs. Hyprland restores `m_vLastFloatingSize` and
    /// `m_vLastFloatingPosition`; `floatingFrames` is that, kept current by the app layer as
    /// the window is dragged.
    ///
    /// A frame is taken as-is only while a usable amount of the window is still on the
    /// monitor, so dragging one half off an edge is never undone on the next render. Anything
    /// less is pulled back. Hyprland never has to think about this; toe does, because hiding a
    /// workspace parks its windows with a single pixel inside the monitor's corner — a frame
    /// captured from a parked window overlaps by 1×1pt, and handing that back would make the
    /// window vanish.
    private func floatingBox(for id: WindowID, on monitor: Monitor) -> Box {
        let stage = floatingStage[id] ?? 1
        guard let remembered = floatingFrames[id] else {
            return centredFloatingBox(on: monitor, stage: stage)
        }

        let onScreen = remembered.intersection(monitor.usable)
        if onScreen.w >= min(Self.minimumOnScreen, remembered.w),
           onScreen.h >= min(Self.minimumOnScreen, remembered.h) {
            return remembered
        }

        // Nowhere useful to put it back: a frame remembered on a display that has since been
        // unplugged, or a window left parked in the stash corner. Centring rather than
        // clamping matters here — an edge-clamped window lands wherever the old geometry
        // happened to point, which on a display that is gone is arbitrary.
        return centredFloatingBox(on: monitor, stage: stage)
    }

    /// Centred on the monitor at a consistent fraction of it, so a floating window is the
    /// same shape whichever window it came from. The aspect cap is what keeps that honest on
    /// a wide display, where a plain width fraction would produce a letterbox.
    private func centredFloatingBox(on monitor: Monitor, stage: Int) -> Box {
        let usable = monitor.usable
        let fraction = floatingSize.fractions(stage: stage)
        let h = min(usable.h * fraction.height, usable.h)
        let w = min(usable.w * fraction.width, usable.w, h * floatingSize.maxAspectRatio)
        return Box(x: usable.minX + (usable.w - w) / 2.0,
                   y: usable.minY + (usable.h - h) / 2.0,
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

    // MARK: - Session

    /// Everything a restart needs to put the layout back. See `SessionSnapshot`.
    ///
    /// - Parameters:
    ///   - boot: token identifying the boot the window ids belong to.
    ///   - monitorKey: durable name for a display. A monitor it cannot name is skipped, and
    ///     the workspaces on it come back on the focused display instead — the same thing
    ///     `setMonitors` does when a display is unplugged.
    public func snapshot(boot: String, monitorKey: (UInt32) -> String?) -> SessionSnapshot {
        var out = SessionSnapshot(boot: boot)

        for index in workspaces.keys.sorted() {
            guard let ws = workspaces[index], let key = monitorKey(ws.monitorID) else { continue }
            out.workspaces.append(WorkspaceSnapshot(index: index,
                                                    monitor: key,
                                                    layout: ws.layout.snapshot(),
                                                    floating: ws.floating.sorted()))
        }

        for (id, index) in activeWorkspace {
            if let key = monitorKey(id) { out.active[key] = index }
        }
        for (id, index) in previousWorkspace {
            if let key = monitorKey(id) { out.previous[key] = index }
        }
        out.focusedMonitor = monitorKey(focusedMonitorID)
        out.focusHistory = focusHistory
        out.floatingFrames = floatingFrames.keys.sorted().map {
            FloatingFrame(window: $0, frame: floatingFrames[$0]!, stage: floatingStage[$0])
        }
        return out
    }

    /// Put a snapshot back. `setMonitors` must have run first — the displays that exist now
    /// are what a restored workspace is homed against.
    ///
    /// Windows named here need not exist yet: on a restart the applications are still running
    /// but their windows arrive through Accessibility over the following second or so, and the
    /// tree has to be waiting for them rather than built around them. Anything that never
    /// turns up is cleared by `reap(keeping:)`.
    ///
    /// - Parameter monitorID: the inverse of `snapshot`'s `monitorKey`.
    public func restore(_ snapshot: SessionSnapshot, monitorID resolve: (String) -> UInt32?) {
        guard !monitors.isEmpty else { return }

        let live = Set(monitors.map(\.id))
        if let key = snapshot.focusedMonitor, let id = resolve(key), live.contains(id) {
            focusedMonitorID = id
        }

        /// A display that has since been unplugged hands its workspaces to the focused one.
        func home(_ key: String) -> UInt32 {
            guard let id = resolve(key), live.contains(id) else { return focusedMonitorID }
            return id
        }

        workspaces.removeAll()
        for saved in snapshot.workspaces {
            guard (1...Self.workspaceCount).contains(saved.index) else { continue }
            let ws = workspace(saved.index, onMonitor: home(saved.monitor))
            ws.monitorID = home(saved.monitor)
            ws.layout.restore(saved.layout)
            ws.floating = Set(saved.floating)
        }

        // A window belongs to exactly one workspace. A file claiming otherwise is resolved in
        // favour of the lowest index, which is the order the workspaces were just built in.
        var seen: Set<WindowID> = []
        for index in workspaces.keys.sorted() {
            guard let ws = workspaces[index] else { continue }
            for id in ws.windows.sorted() where seen.contains(id) {
                ws.layout.remove(id)
                ws.floating.remove(id)
            }
            seen.formUnion(ws.windows)
        }

        // Each monitor shows one workspace and no workspace is shown twice — the invariant
        // `setMonitors` maintains, re-established here against whatever the file says.
        activeWorkspace.removeAll()
        var claimed: Set<Int> = []
        for (key, index) in snapshot.active.sorted(by: { $0.key < $1.key }) {
            guard (1...Self.workspaceCount).contains(index), !claimed.contains(index),
                  let id = resolve(key), live.contains(id), activeWorkspace[id] == nil
            else { continue }
            activeWorkspace[id] = index
            claimed.insert(index)
            workspace(index, onMonitor: id).monitorID = id
        }
        for monitor in monitors where activeWorkspace[monitor.id] == nil {
            let index = firstFreeWorkspaceIndex()
            activeWorkspace[monitor.id] = index
            workspace(index, onMonitor: monitor.id).monitorID = monitor.id
        }

        previousWorkspace.removeAll()
        for (key, index) in snapshot.previous {
            guard (1...Self.workspaceCount).contains(index),
                  let id = resolve(key), live.contains(id) else { continue }
            previousWorkspace[id] = index
        }

        // Only for windows that were actually placed: a frame belonging to nothing would sit
        // in the dictionary for the life of the process, since `reap` only knows about
        // windows it can find on a workspace.
        let placed = seen
        let frames = snapshot.floatingFrames.filter { placed.contains($0.window) }
        floatingFrames = Dictionary(frames.map { ($0.window, $0.frame) },
                                    uniquingKeysWith: { first, _ in first })
        floatingStage = Dictionary(frames.compactMap { f in f.stage.map { (f.window, $0) } },
                                   uniquingKeysWith: { first, _ in first })
        focusHistory = snapshot.focusHistory.filter { placed.contains($0) }

        for ws in workspaces.values {
            guard let m = monitor(id: ws.monitorID) else { continue }
            ws.layout.area = m.usable
            ws.layout.recalculate()
        }
    }

    /// Drop every window a restored snapshot named that has not turned up — applications
    /// that were quit while toe was down, and windows closed in the meantime. Removal goes
    /// through `removeWindow`, so the trees collapse exactly as they would have at the time.
    ///
    /// - Returns: whether anything was dropped, so the caller can skip a re-render.
    @discardableResult
    public func reap(keeping alive: Set<WindowID>) -> Bool {
        var stale: Set<WindowID> = []
        for ws in workspaces.values { stale.formUnion(ws.windows.subtracting(alive)) }
        guard !stale.isEmpty else { return false }

        for id in stale {
            removeWindow(id)          // clears the floating stage too
            floatingFrames.removeValue(forKey: id)
        }
        return true
    }
}

public extension WorkspaceManager {

    /// Whether a workspace holds no windows — cheap enough for the menu bar to ask on every
    /// status refresh.
    func isEmpty(workspace index: Int) -> Bool {
        workspaces[index]?.isEmpty ?? true
    }

    /// Which monitor, if any, is currently showing this workspace.
    func monitorShowing(workspace index: Int) -> UInt32? {
        activeWorkspace.first { $0.value == index }?.key
    }

    /// Whether a workspace is one of the ones you are actually using: it holds windows, or a
    /// monitor is showing it right now. This is what the strip draws as anything but a dim
    /// digit, and what `workspace e+1` cycles through.
    func inUse(workspace index: Int) -> Bool {
        !isEmpty(workspace: index) || monitorShowing(workspace: index) != nil
    }
}
