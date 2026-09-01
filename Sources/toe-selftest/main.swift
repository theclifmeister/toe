import Foundation
import ToeCore

// The tiling area of a 3456×2234 built-in Retina display at its default scaled resolution,
// minus the menu bar. Every expected value below is Hyprland's dwindle output for the same
// geometry with Omarchy's settings: preserve_split = true, force_split = 2.
let AREA = box(0, 0, 1512, 982)

func omarchyLayout(area: Box = AREA) -> DwindleLayout {
    var opts = DwindleOptions()
    opts.preserveSplit = true
    opts.forceSplit = 2
    return DwindleLayout(area: area, options: opts)
}

let h = Harness()

// MARK: - The staircase

h.test("dwindle staircase") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    t.equalBox(l.idealBox(of: 1), box(0, 0, 1512, 982), "single window fills the usable area")

    l.insert(2, anchor: 1)
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 left half")
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 982), "w2 right half (force_split = 2)")

    // The right half is 756 × 982 — taller than wide — so the next split flips to top/bottom.
    l.insert(3, anchor: 2)
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 unchanged")
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 491), "w2 top-right quarter")
    t.equalBox(l.idealBox(of: 3), box(756, 491, 756, 491), "w3 bottom-right quarter")

    // 756 × 491 is wider than tall, so it flips back to left/right.
    l.insert(4, anchor: 3)
    t.equalBox(l.idealBox(of: 3), box(756, 491, 378, 491), "w4 splits w3 side by side")
    t.equalBox(l.idealBox(of: 4), box(1134, 491, 378, 491), "w4 takes the right half")

    // 378 × 491 is taller than wide → top/bottom again.
    l.insert(5, anchor: 4)
    t.equalBox(l.idealBox(of: 4), box(1134, 491, 378, 245.5), "w5 splits w4 top/bottom")
    t.equalBox(l.idealBox(of: 5), box(1134, 736.5, 378, 245.5), "w5 takes the bottom half")
}

h.test("new window splits the focused window, not the last one") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)
    // Focus w1 (the left half) and open there: w1 must split, w2/w3 untouched.
    l.insert(4, anchor: 1)
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 491), "w1 shrinks to its top half")
    t.equalBox(l.idealBox(of: 4), box(0, 491, 756, 491), "w4 takes w1's bottom half")
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 491), "w2 untouched")
    t.equalBox(l.idealBox(of: 3), box(756, 491, 756, 491), "w3 untouched")
}

// MARK: - Insertion fallbacks

// With no focused tiled window to split, Hyprland falls to the leaf under the pointer, then
// to the closest leaf when the pointer sits on a reserved strip, then to the oldest window.

h.test("with no focused window, the leaf under the pointer splits") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)
    // Pointer inside w2's tile. The fail-safe would have picked w1, the oldest.
    l.insert(4, anchor: nil, focalPoint: Point(x: 1000, y: 100))
    t.equalBox(l.idealBox(of: 2), box(756, 0, 378, 491), "w2 shrinks to its left half")
    t.equalBox(l.idealBox(of: 4), box(1134, 0, 378, 491), "w4 takes w2's right half")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 untouched")
    t.equalBox(l.idealBox(of: 3), box(756, 491, 756, 491), "w3 untouched")
}

h.test("a pointer off the tiling area falls to the closest leaf") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)
    // Below the tiling area — the Dock strip, Hyprland's isPointOnReservedArea case.
    // The fail-safe would have picked w1; the closest leaf is w3.
    l.insert(4, anchor: nil, focalPoint: Point(x: 1200, y: 1000))
    t.equalBox(l.idealBox(of: 3), box(756, 491, 378, 491), "w3, the nearest leaf, shrinks to its left half")
    t.equalBox(l.idealBox(of: 4), box(1134, 491, 378, 491), "w4 takes w3's right half")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 untouched")
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 491), "w2 untouched")
}

h.test("the fail-safe leaf is the oldest window, not the leftmost") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.swapSplit(1)   // w2 is now the leftmost leaf, w1 is still the oldest
    t.equalBox(l.idealBox(of: 2), box(0, 0, 756, 982), "w2 moved to the left half")

    l.insert(3, anchor: nil)
    t.equalBox(l.idealBox(of: 1), box(756, 0, 756, 491), "w1 split, the way getFirstNodeOnWorkspace picks it")
    t.equalBox(l.idealBox(of: 3), box(756, 491, 756, 491), "w3 took w1's bottom half")
    t.equalBox(l.idealBox(of: 2), box(0, 0, 756, 982), "w2 untouched")
}

// MARK: - preserve_split

h.test("preserve_split freezes orientation across a resize") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)   // side by side, because 1512 > 982

    // Rotate the display: now much taller than wide.
    l.area = box(0, 0, 982, 1512)
    l.recalculate()

    t.equalBox(l.idealBox(of: 1), box(0, 0, 491, 1512), "still side by side (preserve_split)")
    t.equalBox(l.idealBox(of: 2), box(491, 0, 491, 1512), "orientation was not re-derived")

    // With preserve_split off, Hyprland re-derives the orientation on every recalc.
    var opts = DwindleOptions()
    opts.preserveSplit = false
    opts.forceSplit = 2
    let m = DwindleLayout(area: AREA, options: opts)
    m.insert(1, anchor: nil)
    m.insert(2, anchor: 1)
    m.area = box(0, 0, 982, 1512)
    m.recalculate()
    t.equalBox(m.idealBox(of: 1), box(0, 0, 982, 756), "preserve_split = false flips to top/bottom")
    t.equalBox(m.idealBox(of: 2), box(0, 756, 982, 756), "preserve_split = false flips to top/bottom")
}

// MARK: - Removal

h.test("removal: the sibling absorbs the parent's box") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)

    l.remove(2)
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 unchanged")
    t.equalBox(l.idealBox(of: 3), box(756, 0, 756, 982), "w3 absorbs the whole right half")
    t.equal(l.windowIDs.sorted(), [1, 3], "only two windows remain")

    l.remove(1)
    t.equalBox(l.idealBox(of: 3), box(0, 0, 1512, 982), "last window fills the area")

    l.remove(3)
    t.equal(l.isEmpty, true, "layout empties out")
    t.equal(l.root == nil, true, "root is cleared")
}

h.test("removing a deep leaf collapses only its own parent") { t in
    let l = omarchyLayout()
    for (id, anchor) in [(1, nil), (2, 1), (3, 2), (4, 3)] as [(WindowID, WindowID?)] {
        l.insert(id, anchor: anchor)
    }
    l.remove(4)
    t.equalBox(l.idealBox(of: 3), box(756, 491, 756, 491), "w3 grows back into the full quarter")
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 491), "w2 untouched")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 untouched")
}

// MARK: - swapwindow

h.test("swapwindow exchanges windows without reshaping the tree") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)

    let before = l.idealBoxes().map(\.box).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    l.swap(1, 3)
    let after = l.idealBoxes().map(\.box).sorted { ($0.x, $0.y) < ($1.x, $1.y) }

    t.equal(before, after, "the set of boxes is identical — only the payloads moved")
    t.equalBox(l.idealBox(of: 3), box(0, 0, 756, 982), "w3 now occupies the left half")
    t.equalBox(l.idealBox(of: 1), box(756, 491, 756, 491), "w1 now occupies the bottom-right quarter")
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 491), "w2 untouched")
}

h.test("swapwindow across monitors reshapes neither tree") { t in
    let a = omarchyLayout()
    a.insert(1, anchor: nil)
    a.insert(2, anchor: 1)
    a.insert(3, anchor: 2)

    let b = omarchyLayout(area: box(1512, 0, 1920, 1080))
    b.insert(10, anchor: nil)
    b.insert(11, anchor: 10)

    let beforeA = a.idealBoxes().map(\.box).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    let beforeB = b.idealBoxes().map(\.box).sorted { ($0.x, $0.y) < ($1.x, $1.y) }

    DwindleLayout.swap(3, in: a, with: 11, in: b)

    t.equal(a.idealBoxes().map(\.box).sorted { ($0.x, $0.y) < ($1.x, $1.y) }, beforeA, "tree A keeps its boxes")
    t.equal(b.idealBoxes().map(\.box).sorted { ($0.x, $0.y) < ($1.x, $1.y) }, beforeB, "tree B keeps its boxes")

    t.equalBox(a.idealBox(of: 11), box(756, 491, 756, 491), "w11 took w3's exact slot on A")
    t.equalBox(b.idealBox(of: 3), box(2472, 0, 960, 1080), "w3 took w11's exact slot on B")
    t.equalBox(a.idealBox(of: 1), box(0, 0, 756, 982), "w1 untouched")
    t.equalBox(a.idealBox(of: 2), box(756, 0, 756, 491), "w2 untouched")
    t.equalBox(b.idealBox(of: 10), box(1512, 0, 960, 1080), "w10 untouched")

    t.expect(!a.contains(3) && b.contains(3), "w3 moved to tree B")
    t.expect(!b.contains(11) && a.contains(11), "w11 moved to tree A")
}

// MARK: - Gaps

h.test("gaps: outer on display edges, inner everywhere else") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)

    let f = l.frames(gaps: Gaps(inner: 5, outer: 10))   // Omarchy's gaps_in / gaps_out
    t.equalBox(f[1], box(10, 10, 741, 962), "w1: outer left/top/bottom, inner right")
    t.equalBox(f[2], box(761, 10, 741, 476), "w2: inner left/bottom, outer top/right")
    t.equalBox(f[3], box(761, 496, 741, 476), "w3: inner left/top, outer right/bottom")
}

// MARK: - Directional focus

h.test("movefocus walks the tiling grid by edge adjacency") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)
    let boxes = l.idealBoxes()

    func focus(_ from: WindowID, _ dir: Direction, history: [WindowID] = [3, 2, 1]) -> WindowID? {
        DirectionalSearch.windowInDirection(
            from: l.idealBox(of: from)!, ignoring: from,
            candidates: boxes, direction: dir, focusHistory: history)
    }

    t.equal(focus(3, .left), 1, "left from the bottom-right quarter reaches w1")
    t.equal(focus(3, .up), 2, "up from the bottom-right quarter reaches w2")
    t.equal(focus(2, .down), 3, "down from the top-right quarter reaches w3")
    t.equal(focus(2, .left), 1, "left from the top-right quarter reaches w1")
    t.equal(focus(1, .left), nil, "nothing to the left of the leftmost window")
    t.equal(focus(3, .down), nil, "nothing below the bottom row")
    t.equal(focus(1, .up), nil, "nothing above")
}

h.test("movefocus ties break on focus history, not on shared edge length") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)
    let boxes = l.idealBoxes()

    // w2 and w3 both stick to w1's right edge with an equal shared edge (491 each).
    func focusRight(history: [WindowID]) -> WindowID? {
        DirectionalSearch.windowInDirection(
            from: l.idealBox(of: 1)!, ignoring: 1,
            candidates: boxes, direction: .right, focusHistory: history)
    }
    t.equal(focusRight(history: [2, 3, 1]), 2, "w2 was focused more recently")
    t.equal(focusRight(history: [3, 2, 1]), 3, "w3 was focused more recently")
}

// MARK: - togglesplit

h.test("togglesplit flips the parent split") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 982), "starts side by side")
    l.toggleSplit(2)
    t.equalBox(l.idealBox(of: 1), box(0, 0, 1512, 491), "now stacked")
    t.equalBox(l.idealBox(of: 2), box(0, 491, 1512, 491), "now stacked")
}

// MARK: - Workspaces

h.test("workspaces stash and restore exactly") { t in
    let wm = WorkspaceManager(options: { var o = DwindleOptions(); o.forceSplit = 2; return o }(),
                              gaps: Gaps(inner: 5, outer: 10))
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])

    wm.addWindow(1); wm.addWindow(2); wm.addWindow(3)
    let onWorkspace1 = wm.render()
    t.equal(onWorkspace1.frames.count, 3, "three windows tiled on workspace 1")
    t.equal(onWorkspace1.stashed.isEmpty, true, "nothing stashed yet")

    wm.switchTo(workspace: 2)
    let onWorkspace2 = wm.render()
    t.equal(onWorkspace2.frames.isEmpty, true, "workspace 2 is empty")
    t.equal(onWorkspace2.stashed, [1, 2, 3], "workspace 1's windows are stashed")

    wm.addWindow(4)
    wm.switchTo(workspace: 1)
    let back = wm.render()
    t.equal(back.stashed, [4], "workspace 2's window is now stashed")
    t.equal(back.frames, onWorkspace1.frames, "workspace 1 restores to the exact same frames")
}

h.test("movetoworkspace follows the window") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.noteFocus(2)

    wm.moveFocusedWindow(toWorkspace: 3, follow: true)
    t.equal(wm.focusedWorkspaceIndex, 3, "focus followed the window to workspace 3")
    t.equal(wm.workspaceIndex(of: 2), 3, "w2 lives on workspace 3")
    t.equal(wm.workspaceIndex(of: 1), 1, "w1 stayed behind")
    t.equal(wm.render().stashed, [1], "w1 is stashed")

    wm.noteFocus(2)
    wm.moveFocusedWindow(toWorkspace: 1, follow: false)
    t.equal(wm.focusedWorkspaceIndex, 3, "silent move does not follow")
    t.equal(wm.workspaceIndex(of: 2), 1, "w2 moved anyway")
}

h.test("a floating focus falls back to the window under the pointer") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2); wm.addWindow(3)   // the usual staircase

    wm.addWindow(4, floating: true)                     // focus is now on a floating window
    wm.cursorLocation = { Point(x: 1000, y: 100) }      // pointer sits over w2's tile
    wm.addWindow(5)

    let l = wm.workspaces[wm.focusedWorkspaceIndex]!.layout
    t.equalBox(l.idealBox(of: 2), box(756, 0, 378, 491), "w2, under the pointer, shrinks to its left half")
    t.equalBox(l.idealBox(of: 5), box(1134, 0, 378, 491), "w5 takes w2's right half")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 untouched")
    t.equalBox(l.idealBox(of: 3), box(756, 491, 756, 491), "w3 untouched")
}

// MARK: - Floating

h.test("toggling a window out of the tree and back") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.floatingFrames[2] = box(200, 150, 640, 400)   // seeded at adopt time by the app layer

    wm.noteFocus(2)
    wm.toggleFloating(2)
    t.equal(wm.isFloating(2), true, "w2 floats")
    t.equal(wm.workspaces[1]?.layout.contains(2), false, "and has left the tree")
    t.equalBox(wm.workspaces[1]?.layout.idealBox(of: 1), AREA, "w1 absorbs the whole area")
    t.equalBox(wm.render().floating[2], box(200, 150, 640, 400), "its remembered frame is rendered")

    wm.toggleFloating(2)
    t.equal(wm.isFloating(2), false, "w2 is tiled again")
    t.equalBox(wm.workspaces[1]?.layout.idealBox(of: 1), box(0, 0, 756, 982), "w1 back to the left half")
    t.equalBox(wm.workspaces[1]?.layout.idealBox(of: 2), box(756, 0, 756, 982), "w2 back to the right half")
    t.equal(wm.render().floating.isEmpty, true, "nothing floats any more")
}

h.test("a floating frame is left alone unless it is stranded") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1, floating: true)

    wm.floatingFrames[1] = box(-40, 900, 600, 400)
    t.equalBox(wm.render().floating[1], box(-40, 900, 600, 400),
               "dragged half off an edge: not undone on the next render")

    wm.floatingFrames[1] = box(2000, 1400, 800, 600)   // remembered on a display since unplugged
    t.equalBox(wm.render().floating[1], box(712, 382, 800, 600), "pulled back into the usable area")

    wm.floatingFrames.removeValue(forKey: 1)
    t.equalBox(wm.render().floating[1], box(378, 246, 756, 491), "nothing remembered: centred, half size")
}

h.test("movefocus reaches a floating window") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)                 // left half / right half
    wm.addWindow(3, floating: true)
    wm.floatingFrames[3] = box(756, 0, 400, 300)     // over w2, sharing w1's right edge
    wm.noteFocus(1)

    t.equal(wm.windowInDirection(.right), 3,
            "w2 and the floating w3 both abut w1; the more recently focused w3 wins")
    t.equal(wm.windowInDirection(.left, from: 3), 1, "and it hands focus back")
}

h.test("a floating window keeps its frame across a workspace round trip") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1, floating: true)
    wm.floatingFrames[1] = box(300, 200, 500, 400)

    wm.switchTo(workspace: 2)
    t.equal(wm.render().stashed, [1], "hidden workspace: w1 is stashed")
    t.equal(wm.render().floating.isEmpty, true, "and not rendered as floating")

    wm.switchTo(workspace: 1)
    t.equalBox(wm.render().floating[1], box(300, 200, 500, 400), "comes back exactly where it was")
}

h.test("swapwindow across monitors trades slots, keeping both layouts") { t in
    let left = box(0, 0, 1512, 982)
    let right = box(1512, 0, 1920, 1080)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)])

    let leftWS = wm.activeWorkspace[1]!
    let rightWS = wm.activeWorkspace[2]!
    wm.switchTo(workspace: leftWS)
    wm.addWindow(1); wm.addWindow(2)
    wm.switchTo(workspace: rightWS)
    wm.addWindow(10); wm.addWindow(11)

    wm.noteFocus(2)
    t.equal(wm.swapWindow(.right), true, "w2's right neighbour is w10, on the other monitor")

    t.equal(wm.workspaceIndex(of: 2), rightWS, "w2 now lives on the right monitor's workspace")
    t.equal(wm.workspaceIndex(of: 10), leftWS, "w10 now lives on the left monitor's workspace")
    t.equalBox(wm.workspaces[leftWS]?.layout.idealBox(of: 10), box(756, 0, 756, 982), "w10 took w2's exact slot")
    t.equalBox(wm.workspaces[rightWS]?.layout.idealBox(of: 2), box(1512, 0, 960, 1080), "w2 took w10's exact slot")
    t.equalBox(wm.workspaces[leftWS]?.layout.idealBox(of: 1), box(0, 0, 756, 982), "w1 untouched")
    t.equalBox(wm.workspaces[rightWS]?.layout.idealBox(of: 11), box(2472, 0, 960, 1080), "w11 untouched")
}

h.test("a workspace follows its monitor") { t in
    let left = box(0, 0, 1512, 982)
    let right = box(1512, 0, 1920, 1080)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)])

    // Each monitor gets its own active workspace, as in Hyprland.
    t.equal(Set(wm.activeWorkspace.values).count, 2, "two monitors, two active workspaces")

    wm.switchTo(workspace: 5)
    wm.addWindow(1)
    t.equal(wm.workspaces[5]?.monitorID, wm.focusedMonitorID, "workspace 5 bound to the focused monitor")
    let home = wm.focusedMonitorID
    t.equalBox(wm.workspaces[5]?.layout.idealBox(of: 1), wm.monitor(id: home)!.usable,
               "the window fills its monitor's usable area")

    // Switching to the other monitor's active workspace moves focus there.
    let otherMonitor = wm.monitors.first { $0.id != home }!.id
    let otherWorkspace = wm.activeWorkspace[otherMonitor]!
    wm.switchTo(workspace: otherWorkspace)
    t.equal(wm.focusedMonitorID, otherMonitor, "focus moved to the monitor owning that workspace")

    // And coming back to workspace 5 returns to its own monitor.
    wm.switchTo(workspace: 5)
    t.equal(wm.focusedMonitorID, home, "workspace 5 pulled focus back to its monitor")
}

// MARK: - Config

h.test("the shipped default config parses cleanly") { t in
    let c = try Config.parse(Config.defaultTOML)
    t.equal(c.warnings, [], "no warnings")
    t.equal(c.superKey, Modifiers.option, "SUPER is Option")
    t.equal(c.gaps, Gaps(inner: 5, outer: 10), "Omarchy gaps")
    t.equal(c.dwindle.preserveSplit, true, "preserve_split")
    t.equal(c.dwindle.forceSplit, 2, "force_split")
    t.equal(c.border.activeStart, "#33ccffee", "Omarchy active border gradient start")
    t.equal(c.border.radius, -1, "radius follows the system window corner radius")
    t.equal(c.floatRules.count, 5, "float rules")

    func binding(_ spec: String) -> Binding? { c.bindings.first { $0.source == spec } }

    t.equal(binding("super-left")?.command, .moveFocus(.left), "SUPER+left focuses left")
    t.equal(binding("super-left")?.modifiers, Modifiers.option, "SUPER+left uses Option")
    t.equal(binding("super-left")?.keyCode, 0x7B, "left arrow key code")
    t.equal(binding("super-shift-right")?.command, .swapWindow(.right), "SUPER+SHIFT+right swaps")
    t.equal(binding("super-shift-right")?.modifiers, [.option, .shift], "SUPER+SHIFT")
    t.equal(binding("super-0")?.command, .workspace(.index(10)), "SUPER+0 is workspace 10")
    t.equal(binding("super-shift-0")?.command, .moveToWorkspace(10, follow: true), "SUPER+SHIFT+0")
    t.equal(binding("super-w")?.command, .killActive, "SUPER+W closes")
    t.equal(binding("super-tab")?.command, .workspace(.next), "SUPER+TAB")

    // SUPER+T is not a shipped default — it is a local-config binding, so assert the parser
    // rather than the default table.
    let (mods, code, key) = try BindingParser.parse("super-t", superKey: .option)
    t.equal(mods, Modifiers.option, "super-t: SUPER resolves to Option")
    t.equal(code, 0x11, "super-t: T key code")
    t.equal(key, "t", "super-t: key name")
    t.equal(try CommandParser.parse("togglefloating"), .toggleFloating, "togglefloating dispatcher")

    let arrows = ["super-left", "super-right", "super-up", "super-down"]
    t.equal(arrows.allSatisfy { binding($0) != nil }, true, "all four focus arrows bound")
    t.equal((1...10).allSatisfy { n in c.bindings.contains { $0.command == .workspace(.index(n)) } },
            true, "all ten workspaces bound")
    t.equal((1...10).allSatisfy { n in c.bindings.contains { $0.command == .moveToWorkspace(n, follow: true) } },
            true, "all ten move-to-workspace bindings")

    if case .exec(let cmd)? = binding("super-enter")?.command {
        t.equal(cmd.contains("Ghostty"), true, "SUPER+ENTER launches Ghostty")
        t.equal(cmd.contains("\"Ghostty\""), true, "escaped quotes survive TOML parsing")
    } else {
        t.expect(false, "SUPER+ENTER should be an exec binding")
    }
}

h.test("a negative radius survives the TOML parser") { t in
    let c = try Config.parse("[border]\nradius = -1\n")
    t.equal(c.border.radius, -1, "radius = -1")
    t.equal(c.warnings, [], "no warnings")
}

h.test("border corner radius") { t in
    let big = box(0, 0, 800, 600)
    t.equal(BorderGeometry.effectiveRadius(configured: 12, system: 26, box: big), 12,
            "an explicit radius wins over the system value")
    t.equal(BorderGeometry.effectiveRadius(configured: -1, system: 26, box: big), 26,
            "a negative radius follows the system")
    t.equal(BorderGeometry.effectiveRadius(configured: 0, system: 26, box: big), 0,
            "0 still means square")
    t.equal(BorderGeometry.effectiveRadius(configured: -1, system: 26, box: box(0, 0, 20, 20)), 10,
            "clamped to half the shorter side on a tiny window")
    t.equal(BorderGeometry.outerRadius(inner: 26, width: 2), 28,
            "the band's outer radius clears the window's by the band width")
    t.equal(BorderGeometry.outerRadius(inner: 0, width: 2), 2, "square window, offset band")
}

h.test("binding specs parse in both spellings") { t in
    func parse(_ s: String) -> String? {
        guard let (m, code, name) = try? BindingParser.parse(s, superKey: .option) else { return nil }
        return "\(m.description)|\(code)|\(name)"
    }
    t.equal(parse("SUPER SHIFT, LEFT"), parse("super-shift-left"), "Omarchy and AeroSpace spellings agree")
    t.equal(parse("alt-shift-1"), parse("super+shift+1"), "'+' separators and alt/super alias")
    t.equal(parse("cmd-alt-ctrl-shift-f"), "ctrl-alt-shift-cmd|3|f", "all four modifiers")
    t.equal(parse("super-minus")?.hasSuffix("|27|minus"), true, "'minus' is a key, not a modifier prefix")
    t.equal(parse("super--")?.hasSuffix("|27|-"), true, "a literal '-' key still binds")
    t.equal(parse("super-nonsense"), nil, "unknown key names are rejected")
}

h.test("a bad binding warns instead of failing the whole config") { t in
    let c = try Config.parse("""
    [binds]
    "super-left" = "movefocus l"
    "super-nope" = "movefocus l"
    "super-h"    = "notacommand"
    "super-j"    = "movefocus sideways"
    """)
    t.equal(c.bindings.count, 1, "the one good binding survives")
    t.equal(c.warnings.count, 3, "each bad binding produces a warning")
    t.equal(c.warnings.contains { $0.contains("unknown key 'nope'") }, true, "names the bad key")
    t.equal(c.warnings.contains { $0.contains("unknown command 'notacommand'") }, true, "names the bad command")
}

h.test("TOML errors carry a line number") { t in
    do {
        _ = try TOML.parse("[general]\ngaps_in = 5\ngaps_out\n")
        t.expect(false, "should have thrown")
    } catch let e as TOMLError {
        t.equal(e.line, 3, "reports the offending line")
    }
}

h.test("float rules match by bundle id and title") { t in
    t.equal(FloatRule(app: "com.apple.systempreferences").matches(bundleID: "com.apple.systempreferences", title: "General"), true, "exact bundle id")
    t.equal(FloatRule(app: "com.apple.*").matches(bundleID: "com.apple.finder", title: nil), true, "wildcard suffix")
    t.equal(FloatRule(app: "com.apple.*").matches(bundleID: "com.raycast.macos", title: nil), false, "non-match")
    t.equal(FloatRule(app: "com.apple.finder", title: "Copy").matches(bundleID: "com.apple.finder", title: "Copying 3 items"), true, "title substring")
    t.equal(FloatRule(app: "com.apple.finder", title: "Copy").matches(bundleID: "com.apple.finder", title: "Downloads"), false, "title must match too")
}


h.test("hidden windows park on the monitor's bottom corner") { t in
    // Far off-screen does not work — AppKit clamps it back. The window's top-left corner goes
    // exactly on the monitor's bottom corner instead, leaving one pixel visible.
    let single = Monitor(id: 1, frame: AREA, usable: box(0, 33, 1512, 949))
    let p = Stash.origin(windowSize: Point(x: 800, y: 600), on: single, monitors: [single])
    t.equal(p, Point(x: 1511, y: 981), "bottom-right corner, one pixel inside")

    // With a display to the right, hide to the bottom-left so nothing spills onto it.
    let right = Monitor(id: 2, frame: box(1512, 0, 1920, 1080), usable: box(1512, 0, 1920, 1080))
    let q = Stash.origin(windowSize: Point(x: 800, y: 600), on: single, monitors: [single, right])
    t.equal(q, Point(x: -799, y: 981), "bottom-left, window's right edge one pixel on screen")

    // The right-hand monitor itself still hides to its own bottom-right.
    let r = Stash.origin(windowSize: Point(x: 800, y: 600), on: right, monitors: [single, right])
    t.equal(r, Point(x: 3431, y: 1079), "no neighbour further right")
}

// MARK: - Menu bar summaries

h.test("windows are listed in tree order, floating last") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2); wm.addWindow(3)
    wm.addWindow(9, floating: true)
    wm.addWindow(7, floating: true)

    t.equal(wm.orderedWindows(inWorkspace: 1), [1, 2, 3, 7, 9],
            "tiled left-to-right depth-first, then floating")
    t.equal(wm.orderedWindows(inWorkspace: 4), [], "an untouched workspace is empty")
}

h.test("windows group by application in first-appearance order") { t in
    let names: [WindowID: String] = [1: "Ghostty", 2: "Google Chrome", 3: "Ghostty",
                                     4: "Safari", 5: "Google Chrome"]
    let groups = AppGrouping.group([1, 2, 3, 4, 5]) { names[$0] }

    t.equal(groups.map(\.name), ["Ghostty", "Google Chrome", "Safari"],
            "ordered by where each app first appears, not alphabetically")
    t.equal(groups.map(\.count), [2, 2, 1], "windows per app")
    t.equal(groups.first?.windows, [1, 3], "selecting the row focuses the first window")

    // A window whose application cannot be named is dropped rather than shown blank.
    t.equal(AppGrouping.group([1, 99]) { names[$0] }.map(\.name), ["Ghostty"], "unnamed windows skipped")
    t.equal(AppGrouping.group([]) { names[$0] }.isEmpty, true, "no windows, no groups")
}

h.test("a workspace knows which monitor is showing it") { t in
    let left = box(0, 0, 1512, 982), right = box(1512, 0, 1920, 1080)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)])
    wm.switchTo(workspace: 4)
    let home = wm.focusedMonitorID

    t.equal(wm.monitorShowing(workspace: 4), home, "workspace 4 is on the focused monitor")
    t.equal(wm.monitorShowing(workspace: 9), nil, "workspace 9 is not on screen")
    t.equal(wm.visibleWorkspaceIndices.count, 2, "one visible workspace per monitor")
}

h.test("the strip shows occupied and visible workspaces") { t in
    let items = WorkspaceStrip.items(for: [
        WorkspaceStrip.State(index: 1, isFocused: true, isVisible: true, isEmpty: false),
        WorkspaceStrip.State(index: 3, isFocused: false, isVisible: false, isEmpty: true),
        WorkspaceStrip.State(index: 7, isFocused: false, isVisible: false, isEmpty: false),
    ])
    t.equal(items.map(\.index), [1, 7], "an empty off-screen workspace gets no slot")
    t.equal(items.map(\.dim), [false, false], "occupied workspaces are full contrast")

    // The one you are on is always there, even with nothing on it — dimmed, the way waybar's
    // `#workspaces button.empty { opacity: 0.5 }` dims it.
    let onEmpty = WorkspaceStrip.items(for: [
        WorkspaceStrip.State(index: 5, isFocused: true, isVisible: true, isEmpty: true)])
    t.equal(onEmpty.map(\.index), [5], "the focused workspace keeps its slot when empty")
    t.equal(onEmpty.map(\.dim), [true], "and is dimmed")
    t.equal(WorkspaceStrip.items(for: []).isEmpty, true, "nothing in, nothing out")
}

h.test("workspace ten is labelled zero") { t in
    let items = WorkspaceStrip.items(for: (1...10).map {
        WorkspaceStrip.State(index: $0, isFocused: false, isVisible: false, isEmpty: false) })
    t.equal(items.map(\.label), ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            "workspace 10 shows as 0, as Omarchy's format-icons do")
}

h.test("markers follow focus and visibility") { t in
    let items = WorkspaceStrip.items(for: [
        WorkspaceStrip.State(index: 1, isFocused: true, isVisible: true, isEmpty: false),
        WorkspaceStrip.State(index: 2, isFocused: false, isVisible: true, isEmpty: false),
        WorkspaceStrip.State(index: 4, isFocused: false, isVisible: false, isEmpty: false),
    ])
    t.equal(items.map(\.marker), [.focused, .visible, .digit],
            "a filled square where you are, outlined on another display, a digit off-screen")
}

h.test("clicking the strip picks the workspace under the pointer") { t in
    // Three 8pt items, 7pt apart, centred in a 60pt button: they start at 11, 26 and 41.
    func hit(_ x: Double) -> Int? {
        WorkspaceStrip.hit(x: x, widths: [8, 8, 8], gap: 7, buttonWidth: 60)
    }
    t.equal(hit(15), .some(0), "on the first item")
    t.equal(hit(30), .some(1), "on the middle item")
    t.equal(hit(45), .some(2), "on the last item")

    // The gaps are not dead: they belong to whichever neighbour is nearer.
    t.equal(hit(21), .some(0), "just past the first item")
    t.equal(hit(24), .some(1), "just before the second")

    t.equal(hit(5), nil, "the padding before the strip opens the menu instead")
    t.equal(hit(55), nil, "and so does the padding after it")
    t.equal(WorkspaceStrip.hit(x: 30, widths: [], gap: 7, buttonWidth: 60), nil, "no items, no hit")
}

exit(h.report())
