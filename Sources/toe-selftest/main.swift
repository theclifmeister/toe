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
    t.equalBox(wm.render().floating[2], box(227, 98, 1058, 786),
               "centred, 70% wide by 80% tall — the same box whichever window it came from")

    wm.floatingFrames[2] = box(40, 40, 640, 400)   // dragged into the corner by hand
    t.equalBox(wm.render().floating[2], box(40, 40, 640, 400),
               "a drag is not pulled back to the centre on the next render")

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
    t.equalBox(wm.render().floating[1], box(227, 98, 1058, 786), "centred at the standard floating size")

    // Hiding a workspace parks a window one pixel inside the monitor's corner. Adopting a
    // window that was left parked — toe killed rather than quit — captures that as its
    // floating frame, and handing it straight back would make the window vanish.
    wm.floatingFrames[1] = box(1511, 981, 800, 600)
    t.equalBox(wm.render().floating[1], box(227, 98, 1058, 786),
               "a 1pt sliver on screen is not enough to take a frame at face value")

    wm.floatingFrames.removeValue(forKey: 1)
    t.equalBox(wm.render().floating[1], box(227, 98, 1058, 786), "nothing remembered: the same centred box")
}

h.test("a floating window is centred when its display is disconnected") { t in
    let left = box(0, 0, 1512, 982)
    let right = box(1512, 0, 1920, 1080)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)])

    wm.addWindow(1, floating: true)                   // workspace 1, on the left display
    wm.floatingFrames[1] = box(300, 200, 800, 600)
    t.equalBox(wm.render().floating[1], box(300, 200, 800, 600), "left exactly where it was put")

    // The left display is unplugged. Workspace 1 re-homes to what is left of the desk.
    wm.setMonitors([Monitor(id: 2, frame: right, usable: right)])
    wm.switchTo(workspace: 1)
    t.equalBox(wm.render().floating[1], box(1800, 108, 1344, 864),
               "centred on the remaining display, sized to it")
}

h.test("a floating window is not a letterbox on an ultrawide") { t in
    let wide = box(0, 0, 5120, 1410)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: wide, usable: wide)])
    wm.addWindow(1); wm.addWindow(2)
    wm.noteFocus(2)
    wm.toggleFloating(2)

    // 80% of 1410 is 1128 tall. A plain 70% of 5120 would be 3584 wide — instead the window
    // stops at 1.6 times its own height.
    t.equalBox(wm.render().floating[2], box(1658, 141, 1805, 1128),
               "width capped by max_aspect_ratio, still centred")

    wm.floatingSize.maxAspectRatio = 100                 // effectively uncapped
    wm.noteFocus(2)
    wm.toggleFloating(2); wm.toggleFloating(2)           // re-float to re-centre
    t.equalBox(wm.render().floating[2], box(768, 141, 3584, 1128), "uncapped, it is the full 70%")
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

// MARK: - Dragging

/// Four windows opened in order on one monitor, each splitting the one before it:
///
///     ┌────────┬────────┐
///     │        │   w2   │
///     │   w1   ├───┬────┤
///     │        │w3 │ w4 │
///     └────────┴───┴────┘
func draggingFixture() -> WorkspaceManager {
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2); wm.addWindow(3); wm.addWindow(4)
    return wm
}

h.test("dragging a window over a tile trades their places") { t in
    let wm = draggingFixture()
    let layout = wm.focusedWorkspace.layout
    t.equalBox(layout.idealBox(of: 1), box(0, 0, 756, 982), "fixture: w1")
    t.equalBox(layout.idealBox(of: 2), box(756, 0, 756, 491), "fixture: w2")
    t.equalBox(layout.idealBox(of: 3), box(756, 491, 378, 491), "fixture: w3")
    t.equalBox(layout.idealBox(of: 4), box(1134, 491, 378, 491), "fixture: w4")

    t.equal(wm.swapWithWindow(at: Point(x: 1000, y: 100), dragging: 1), true, "the pointer is over w2")

    t.equalBox(layout.idealBox(of: 1), box(756, 0, 756, 491), "w1 took w2's slot")
    t.equalBox(layout.idealBox(of: 2), box(0, 0, 756, 982), "w2 took w1's")
    t.equalBox(layout.idealBox(of: 3), box(756, 491, 378, 491), "w3 untouched — only the payloads moved")
    t.equalBox(layout.idealBox(of: 4), box(1134, 491, 378, 491), "and w4")
}

h.test("a drag settles: the tile under the pointer now holds the dragged window") { t in
    let wm = draggingFixture()
    let point = Point(x: 1000, y: 100)

    t.equal(wm.swapWithWindow(at: point, dragging: 1), true, "first move onto w2 swaps")
    t.equal(wm.swapWithWindow(at: point, dragging: 1), false,
            "every further move inside that tile is a no-op: it holds w1 now")
    t.equal(wm.swapWithWindow(at: Point(x: 300, y: 300), dragging: 1), true,
            "moving on to a different tile swaps again")
    t.equalBox(wm.focusedWorkspace.layout.idealBox(of: 1), box(0, 0, 756, 982), "w1 ended up where it started")
}

h.test("dragging is not restricted to neighbours the way swapwindow is") { t in
    let wm = draggingFixture()
    wm.noteFocus(4)
    t.equal(wm.swapWindow(.left), true, "the keyboard can only reach w4's neighbour, w3")
    t.equalBox(wm.focusedWorkspace.layout.idealBox(of: 4), box(756, 491, 378, 491), "w4 moved one slot left")

    let wm2 = draggingFixture()
    t.equal(wm2.swapWithWindow(at: Point(x: 300, y: 300), dragging: 4), true, "the pointer reaches w1 directly")
    t.equalBox(wm2.focusedWorkspace.layout.idealBox(of: 4), box(0, 0, 756, 982), "w4 crossed the tree in one drag")
    t.equalBox(wm2.focusedWorkspace.layout.idealBox(of: 1), box(1134, 491, 378, 491), "w1 came the other way")
}

h.test("dragging onto another monitor takes the window and the focus there") { t in
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
    t.equal(wm.focusedMonitorID, 1, "the drag starts on the left monitor")

    t.equal(wm.swapWithWindow(at: Point(x: 3000, y: 500), dragging: 2), true, "the pointer is over w11")

    t.equal(wm.workspaceIndex(of: 2), rightWS, "w2 now lives on the right monitor's workspace")
    t.equal(wm.workspaceIndex(of: 11), leftWS, "and w11 on the left one's")
    t.equalBox(wm.workspaces[rightWS]?.layout.idealBox(of: 2), box(2472, 0, 960, 1080), "w2 took w11's exact slot")
    t.equalBox(wm.workspaces[leftWS]?.layout.idealBox(of: 11), box(756, 0, 756, 982), "w11 took w2's")
    t.equalBox(wm.workspaces[rightWS]?.layout.idealBox(of: 10), box(1512, 0, 960, 1080), "w10 untouched")
    t.equal(wm.focusedMonitorID, 2, "focus followed the window across")
}

h.test("only tiled windows are dragged, and only onto tiles") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.addWindow(3, floating: true)
    wm.floatingFrames[3] = box(800, 100, 400, 300)          // sitting over w2

    t.equal(wm.swapWithWindow(at: Point(x: 300, y: 300), dragging: 3), false,
            "a floating window is dragged by its app alone; toe just remembers where it lands")

    t.equal(wm.swapWithWindow(at: Point(x: 900, y: 200), dragging: 1), true,
            "dragging over the floating w3 swaps with the tile underneath it")
    t.equalBox(wm.focusedWorkspace.layout.idealBox(of: 1), box(756, 0, 756, 982), "w1 took w2's slot")

    t.equal(wm.swapWithWindow(at: Point(x: -500, y: -500), dragging: 1), false,
            "a pointer on no monitor at all is not a drop target")
}

// MARK: - Config

h.test("the shipped default config parses cleanly") { t in
    let c = try Config.parse(Config.defaultTOML)
    t.equal(c.warnings, [], "no warnings")
    t.equal(c.superKey, Modifiers.option, "SUPER is Option")
    t.equal(c.gaps, Gaps(inner: 5, outer: 10), "Omarchy gaps")
    t.equal(c.bar.persistentWorkspaces, 5, "Omarchy's persistent-workspaces 1-5")
    t.equal(c.dwindle.preserveSplit, true, "preserve_split")
    t.equal(c.dwindle.forceSplit, 2, "force_split")
    t.equal(c.border.activeStart, "#33ccffee", "Omarchy active border gradient start")
    t.equal(c.border.radius, -1, "radius follows the system window corner radius")
    t.equal(c.floatRules.count, 5, "float rules")
    t.equal(c.floating.width, 0.70, "floating width fraction")
    t.equal(c.floating.height, 0.80, "floating height fraction")
    t.equal(c.floating.maxAspectRatio, 1.6, "floating max aspect ratio")

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

    t.equal(binding("super-t")?.command, .toggleFloating, "SUPER+T floats")
    t.equal(binding("super-t")?.keyCode, 0x11, "T key code")
    t.equal(binding("super-shift-v"), nil, "SUPER+SHIFT+V is no longer bound")

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

h.test("persistent_workspaces is configurable and range-checked") { t in
    let off = try Config.parse("[bar]\npersistent_workspaces = 0\n")
    t.equal(off.bar.persistentWorkspaces, 0, "0 turns persistent slots off")
    t.equal(off.warnings, [], "no warnings")

    let all = try Config.parse("[bar]\npersistent_workspaces = 10\n")
    t.equal(all.bar.persistentWorkspaces, 10, "10 keeps every workspace on the bar")

    let bad = try Config.parse("[bar]\npersistent_workspaces = 99\n")
    t.equal(bad.bar.persistentWorkspaces, 5, "an out-of-range value keeps the default")
    t.equal(bad.warnings.contains { $0.contains("bar.persistent_workspaces") }, true,
            "and says so in the menu bar")
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
    // persistent: 0 is the strip with nothing kept back — every slot has to be earned.
    let items = WorkspaceStrip.items(for: [
        WorkspaceStrip.State(index: 1, isFocused: true, isVisible: true, isEmpty: false),
        WorkspaceStrip.State(index: 3, isFocused: false, isVisible: false, isEmpty: true),
        WorkspaceStrip.State(index: 7, isFocused: false, isVisible: false, isEmpty: false),
    ], persistent: 0)
    t.equal(items.map(\.index), [1, 7], "an empty off-screen workspace gets no slot")
    t.equal(items.map(\.dim), [false, false], "occupied workspaces are full contrast")

    // The one you are on is always there, even with nothing on it — dimmed, the way waybar's
    // `#workspaces button.empty { opacity: 0.5 }` dims it.
    let onEmpty = WorkspaceStrip.items(for: [
        WorkspaceStrip.State(index: 5, isFocused: true, isVisible: true, isEmpty: true)],
        persistent: 0)
    t.equal(onEmpty.map(\.index), [5], "the focused workspace keeps its slot when empty")
    t.equal(onEmpty.map(\.dim), [true], "and is dimmed")
    t.equal(WorkspaceStrip.items(for: [], persistent: 0).isEmpty, true, "nothing in, nothing out")
}

h.test("the strip keeps Omarchy's persistent workspaces") { t in
    // Omarchy's waybar declares persistent-workspaces 1-5: they are on the bar whether or
    // not anything is on them, dimmed while empty.
    func states(occupied: Set<Int>, focused: Int) -> [WorkspaceStrip.State] {
        (1...WorkspaceManager.workspaceCount).map {
            WorkspaceStrip.State(index: $0, isFocused: $0 == focused, isVisible: $0 == focused,
                                 isEmpty: !occupied.contains($0))
        }
    }

    let fresh = WorkspaceStrip.items(for: states(occupied: [1], focused: 1))
    t.equal(fresh.map(\.index), [1, 2, 3, 4, 5], "five slots with one workspace in use")
    t.equal(fresh.map(\.marker), [.focused, .digit, .digit, .digit, .digit],
            "a square where you are, digits for the rest")
    t.equal(fresh.map(\.dim), [false, true, true, true, true], "the empty four are dimmed")

    let beyond = WorkspaceStrip.items(for: states(occupied: [1, 8], focused: 1))
    t.equal(beyond.map(\.index), [1, 2, 3, 4, 5, 8],
            "a workspace past the persistent five appears once it has windows")

    t.equal(WorkspaceStrip.items(for: states(occupied: [1], focused: 1), persistent: 10)
                .map(\.index), Array(1...10), "persistent 10 shows all ten")
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

// MARK: - The quick menu

/// A context with three windows spread over two workspaces, so the Windows and Workspaces levels
/// have something real to be built from.
func menuFixture() -> MenuContext {
    let ws1 = WorkspaceSummary(
        index: 1, isFocused: true, isVisible: true, monitorName: nil,
        apps: [AppSummary(name: "Ghostty", windowCount: 2, pid: 501,
                          representativeWindow: 1001, windowTitle: "~/src/toe"),
               AppSummary(name: "Safari", windowCount: 1, pid: 502,
                          representativeWindow: 1002, windowTitle: "Hyprland Wiki")])
    let ws4 = WorkspaceSummary(
        index: 4, isFocused: false, isVisible: false, monitorName: nil,
        apps: [AppSummary(name: "Google Chrome", windowCount: 1, pid: 503,
                          representativeWindow: 1003, windowTitle: "Inbox")])
    let others = [2, 3, 5, 6, 7, 8, 9, 10].map {
        WorkspaceSummary(index: $0, isFocused: false, isVisible: false, monitorName: nil, apps: [])
    }
    let config = Config.makeDefault()
    return MenuContext(workspaces: ([ws1, ws4] + others).sorted { $0.index < $1.index },
                       focusedWindow: 1001,
                       focusedWorkspace: 1,
                       config: config,
                       version: "0.2.0")
}

h.test("menu parses as a command and round-trips") { t in
    t.equal(try? CommandParser.parse("menu"), .some(.menu), "the dispatcher exists")
    // Like `reload`, a trailing argument is ignored rather than rejected — the house style for
    // commands that take none.
    t.equal(try? CommandParser.parse("menu extra"), .some(.menu), "an argument is ignored")

    let every: [Command] = [
        .moveFocus(.left), .moveFocus(.right), .moveFocus(.up), .moveFocus(.down),
        .swapWindow(.left), .moveWindow(.down),
        .workspace(.index(1)), .workspace(.index(10)),
        .workspace(.next), .workspace(.previous), .workspace(.former),
        .moveToWorkspace(3, follow: true), .moveToWorkspace(7, follow: false),
        .killActive, .toggleFloating, .toggleSplit, .swapSplit,
        .exec("osascript -e 'tell application \"Ghostty\" to new window'"),
        .reload, .menu,
    ]
    for command in every {
        t.equal(try? CommandParser.parse(command.described), .some(command),
                "\(command.described) round-trips")
    }
}

h.test("the shipped config binds SUPER+SPACE to the menu") { t in
    let config = try! Config.parse(Config.defaultTOML)
    let binding = config.bindings.first { $0.command == .menu }
    t.expect(binding != nil, "the default config binds the menu")
    t.equal(binding?.keyCode, .some(0x31), "kVK_Space")
    t.equal(binding?.modifiers, .some(Modifiers.option), "SUPER is Option by default")
    t.equal(binding?.source, .some("super-space"), "written the way Omarchy writes it")
}

h.test("the root menu drills into seven destinations") { t in
    let root = MenuTree.root(menuFixture())
    t.equal(root.children.map(\.id),
            ["windows", "workspaces", "layout", "style", "setup", "system", "about"],
            "Omarchy's shape, minus the pacman-shaped sections")
    t.expect(root.children.allSatisfy(\.isSubmenu), "every top-level row drills down")
}

h.test("the Windows level puts this workspace first and the rest one level down") { t in
    let rows = MenuTree.windows(menuFixture())
    t.equal(rows.map(\.id), ["windows.1001", "windows.1002", "windows.elsewhere"],
            "the focused workspace's apps, then everything else")
    t.equal(rows[0].title, "Ghostty  ×2", "grouped apps carry their count")
    t.equal(rows[0].detail, .some("~/src/toe"), "and the window's current title")
    t.equal(rows[1].title, "Safari", "a single window needs no count")

    let elsewhere = rows[2].children
    t.equal(elsewhere.map(\.id), ["windows.1003"], "one window on workspace 4")
    t.equal(elsewhere[0].detail, .some("Workspace 4"), "which says where it is")

    let empty = MenuTree.windows(MenuContext.empty)
    t.equal(empty.map(\.id), ["windows.none"], "and an honest empty case")
    t.expect(!empty[0].isSelectable, "which you cannot activate")
}

h.test("workspace rows keep all ten slots and tick the one you are on") { t in
    let rows = MenuTree.workspaces(menuFixture())
    let numbered = rows.filter { $0.id.hasPrefix("workspaces.") && Int($0.id.dropFirst(11)) != nil }
    t.equal(numbered.count, 10, "all ten, whatever the bar shows")
    t.equal(numbered.filter(\.isOn).map(\.id), ["workspaces.1"], "exactly one is current")
    t.equal(numbered[3].detail, .some("1 window"), "workspace 4 says what is on it")
    t.equal(numbered[1].detail, .some("empty"), "and an empty one says so")

    if case .action(.command(.workspace(.index(let n)))) = numbered[6].kind {
        t.equal(n, 7, "row seven switches to workspace seven, through the same dispatcher")
    } else {
        t.expect(false, "workspace rows dispatch a command")
    }

    let move = rows.first { $0.id == "workspaces.move" }
    t.expect(move?.isEnabled == true, "move-to is available with a focused window")
    t.expect(move?.children.first { $0.id == "workspaces.move.1" }?.isEnabled == false,
             "except to the workspace you are already on")

    var noWindow = menuFixture()
    noWindow.focusedWindow = nil
    let disabled = MenuTree.workspaces(noWindow).first { $0.id == "workspaces.move" }
    t.expect(disabled?.isEnabled == false, "and not at all without one")
}

h.test("layout rows need a window and show the user's own shortcut") { t in
    let rows = MenuTree.layout(menuFixture())
    t.equal(rows.map(\.id), ["layout.togglesplit", "layout.swapsplit", "layout.togglefloating",
                             "layout.killactive", "layout.swap"],
            "the four commands toe has, plus the swap directions")
    t.equal(rows[0].detail, .some("alt-j"), "read live from the config, not hardcoded")
    t.equal(rows[3].detail, .some("alt-w"), "so a rebound key is never misreported")

    var noWindow = menuFixture()
    noWindow.focusedWindow = nil
    t.expect(MenuTree.layout(noWindow).allSatisfy { !$0.isEnabled },
             "all of them are disabled with nothing focused")
}

h.test("the style level ticks the running theme and gaps") { t in
    let rows = MenuTree.style(menuFixture())
    t.equal(rows.map(\.id), ["style.theme", "style.gaps", "style.border"], "three groups")

    let themes = rows[0].children
    t.equal(themes.filter(\.isOn).map(\.id), ["style.theme.toe"],
            "the shipped gradient is toe's own theme")

    let gaps = rows[1].children
    t.equal(gaps.filter(\.isOn).map(\.id), ["style.gaps.omarchy"],
            "and 5/10 is Omarchy's")

    var recoloured = menuFixture()
    recoloured.config.border.activeStart = "#7AA2F7EE"      // upper case on purpose
    recoloured.config.border.activeEnd = "#bb9af7ee"
    t.equal(MenuTree.style(recoloured)[0].children.filter(\.isOn).map(\.id),
            ["style.theme.tokyonight"], "matched on colour, not on how the hex is spelled")
}

h.test("BorderTheme.matching only claims a theme it really is") { t in
    t.equal(BorderTheme.matching(BorderConfig())?.id, .some("toe"), "the default is toe's own")
    var odd = BorderConfig()
    odd.activeStart = "#123456ff"
    odd.activeEnd = "#654321ff"
    t.expect(BorderTheme.matching(odd) == nil, "a hand-picked gradient matches nothing")
}

h.test("the setup level offers the LaunchAgent escape hatch instead of the toggle") { t in
    var context = menuFixture()
    context.startAtLogin = .off
    t.expect(MenuTree.setup(context).contains { $0.id == "setup.startatlogin" },
             "normally you get a toggle")

    context.startAtLogin = .legacyLaunchAgent
    let rows = MenuTree.setup(context)
    t.expect(!rows.contains { $0.id == "setup.startatlogin" },
             "but not while a LaunchAgent would launch a second toe")
    t.expect(rows.contains { $0.id == "setup.legacylaunchagent" },
             "you get the removal row instead")
}

h.test("only restart and shut down ask twice, and the safe row comes first") { t in
    t.equal(SystemAction.allCases.filter(\.needsConfirmation), [.restart, .shutDown],
            "log out raises the system's own dialog, so confirming it here would double up")

    let rows = MenuTree.confirmation(.restart)
    t.equal(rows.map(\.id), ["confirm.no", "confirm.yes"],
            "asked as two rows, with Cancel first")
    t.expect(!rows[0].isSelectable, "Cancel is a label; ESC is the key that means it")

    // A fresh level preselects row 0, so the row ENTER lands on must be the one that does nothing.
    var menu = MenuState(root: MenuEntry(id: "root", title: "Go", kind: .submenu([])),
                         visibleRows: 12)
    menu.push(title: "Restart", items: rows)
    t.equal(menu.selection, 0, "the selection starts on Cancel")
    t.equal(menu.handle(.enter), .ignored, "so ENTER twice in a row cannot restart your Mac")
    t.equal(menu.handle(.down), .redraw, "you have to move to the row that acts")
    t.equal(menu.handle(.enter), .perform(.system(.restart)), "and then it does")
    t.equal(menu.handle(.escape), .redraw, "ESC backs out of the question")
}

h.test("the about level generates keybindings from the live config") { t in
    let context = menuFixture()
    let keys = MenuTree.about(context).first { $0.id == "about.keybindings" }?.children ?? []
    t.equal(keys.count, context.config.bindings.count, "every binding, and only those")
    let split = keys.first { $0.detail == "togglesplit" }
    t.equal(split?.title, .some("alt-j"), "shown as the shortcut it is")
    if case .action(.command(let c)) = split?.kind {
        t.equal(c, .toggleSplit, "and the row runs it, not just describes it")
    } else {
        t.expect(false, "keybinding rows dispatch their command")
    }
}

h.test("fuzzy match prefers word starts and runs") { t in
    func s(_ q: String, _ c: String) -> Int? { FuzzyMatch.score(q, in: c)?.score }

    t.expect(s("sf", "Safari") ?? -999 > s("sf", "Transfer files") ?? 999,
             "initials beat letters buried mid-word")
    t.expect(s("tog", "Toggle floating") ?? -999 > s("tog", "Back to last visited group") ?? 999,
             "a consecutive run beats a scattered one")
    t.expect(s("nord", "Nord") ?? -999 > s("nord", "Nord Extended Theme") ?? 999,
             "and the shorter candidate wins a tie")
    t.expect(s("SAF", "Safari") != nil, "matching is case-insensitive")
    t.expect(s("xyz", "Safari") == nil, "a non-subsequence does not match at all")
    t.equal(FuzzyMatch.score("", in: "Safari")?.offsets, .some([]), "an empty query matches with no highlight")
    t.equal(FuzzyMatch.score("sfr", in: "Safari")?.offsets, .some([0, 2, 4]),
            "offsets point at the characters that matched")
}

h.test("ranking is stable, so ten workspaces stay in order") { t in
    let entries = (1...10).map {
        MenuEntry.action("w.\($0)", "Workspace \($0)", .command(.workspace(.index($0))))
    }
    t.equal(FuzzyMatch.rank("", entries).map(\.entry.id), entries.map(\.id),
            "an empty query keeps the original order")
    t.equal(FuzzyMatch.rank("workspace", entries).map(\.entry.id), entries.map(\.id),
            "and so does a query every row scores the same on")
}

h.test("keywords match but never highlight") { t in
    let entries = [
        MenuEntry.action("a", "Sleep display", .system(.sleepDisplay), keywords: ["monitor"]),
        MenuEntry.action("b", "Monitor layout", .command(.reload)),
    ]
    let rows = FuzzyMatch.rank("monitor", entries)
    t.equal(rows.map(\.entry.id), ["b", "a"], "a title match outranks a keyword match")
    t.equal(rows[1].offsets, [], "a keyword hit shows no highlighting rather than misleading it")
}

h.test("CTRL+N and CTRL+P move like the arrows, and Option-held still types letters") { t in
    func key(_ code: UInt32, _ chars: String, _ mods: Modifiers = []) -> MenuKey? {
        MenuKey.from(keyCode: code, characters: chars, modifiers: mods)
    }

    t.equal(key(0x2D, "n", .control), .some(.down), "ctrl-n")
    t.equal(key(0x23, "p", .control), .some(.up), "ctrl-p")
    t.equal(key(0x0D, "w", .control), .some(.deleteWord), "ctrl-w")
    t.equal(key(0x20, "u", .control), .some(.clearLine), "ctrl-u")
    t.equal(key(0x00, "a", .control), .some(.home), "ctrl-a")
    t.equal(key(0x0E, "e", .control), .some(.end), "ctrl-e")

    t.equal(key(0x7E, ""), .some(.up), "the up arrow")
    t.equal(key(0x24, "\r"), .some(.enter), "return")
    t.equal(key(0x35, "\u{1B}"), .some(.escape), "escape")
    t.equal(key(0x33, "\u{7F}"), .some(.backspace), "backspace")

    // The regression this whole mapping exists for. SUPER is Option, so someone who opens the
    // menu with ⌥Space and keeps ⌥ down must still be typing letters — `charactersIgnoringModifiers`
    // gives "a" where `characters` would have given "å".
    t.equal(key(0x00, "a", .option), .some(.character("a")), "option-a is still an a")
    t.equal(key(0x11, "t", [.option, .shift]), .some(.character("t")), "and so is option-shift-t")

    t.expect(key(0x0C, "q", .command) == nil, "⌘Q is never the menu's to take")
    t.expect(key(0x30, "\t", .command) == nil, "nor ⌘Tab")
}

/// Twenty rows, so scrolling has somewhere to go.
func longMenu(visible: Int) -> MenuState {
    let items = (1...20).map { MenuEntry.action("row.\($0)", "Row \($0)", .command(.reload)) }
    return MenuState(root: MenuEntry(id: "root", title: "Go", kind: .submenu(items)),
                     visibleRows: visible)
}

h.test("typing filters and puts the selection back at the top") { t in
    var menu = MenuState(root: MenuTree.root(menuFixture()), visibleRows: 12)
    t.equal(menu.rows.count, 7, "everything, to begin with")
    t.equal(menu.handle(.down), .redraw, "move down one")
    t.equal(menu.selection, 1, "so the selection is on the second row")

    t.equal(menu.handle(.character("s")), .redraw, "start typing")
    t.equal(menu.selection, 0, "and the selection returns to the top")
    // Still seven: `s` reaches every row, several of them only through a keyword — "layout" by
    // "split", "about" by "keybindings". Broadening like that is the point of keywords.
    t.equal(menu.rows.count, 7, "a single letter can still reach everything")

    for c in "ty" { _ = menu.handle(.character(c)) }
    t.expect(menu.rows.count < 7, "two more characters narrow it")

    for c in "le" { _ = menu.handle(.character(c)) }
    t.equal(menu.rows.map(\.entry.id), ["style"], "down to one match")
    t.equal(menu.query, "style", "and the query reads back")
}

h.test("the selection wraps and keeps itself in view") { t in
    var menu = longMenu(visible: 5)
    t.equal(menu.scrollOffset, 0, "starts at the top")

    for _ in 0..<4 { _ = menu.handle(.down) }
    t.equal(menu.selection, 4, "the last visible row")
    t.equal(menu.scrollOffset, 0, "needs no scrolling yet")

    _ = menu.handle(.down)
    t.equal(menu.selection, 5, "one further")
    t.equal(menu.scrollOffset, 1, "scrolls by exactly one, not a page")

    _ = menu.handle(.up)
    t.equal(menu.scrollOffset, 1, "coming back up does not scroll again")

    _ = menu.handle(.end)
    t.equal(menu.selection, 19, "End goes to the last row")
    t.equal(menu.scrollOffset, 15, "with the window against the bottom")

    _ = menu.handle(.down)
    t.equal(menu.selection, 0, "and one more wraps to the top")
    t.equal(menu.scrollOffset, 0, "bringing the window with it")

    _ = menu.handle(.up)
    t.equal(menu.selection, 19, "wrapping backwards too")
}

h.test("ENTER descends, ESC comes back, and ESC at the root dismisses") { t in
    var menu = MenuState(root: MenuTree.root(menuFixture()), visibleRows: 12)
    t.equal(menu.depth, 0, "at the root")
    t.equal(menu.prompt, "Go…", "walker's prompt")

    for c in "layout" { _ = menu.handle(.character(c)) }
    t.equal(menu.handle(.enter), .redraw, "ENTER on a submenu descends rather than performing")
    t.equal(menu.depth, 1, "one level down")
    t.equal(menu.query, "", "with the query cleared")
    t.equal(menu.breadcrumb, ["Go", "Layout"], "and a trail back")

    t.equal(menu.handle(.escape), .redraw, "ESC pops")
    t.equal(menu.depth, 0, "back at the root")
    t.equal(menu.handle(.escape), .dismiss, "and ESC there closes the menu")
}

h.test("BACKSPACE edits the query but never backs out of the menu") { t in
    var menu = MenuState(root: MenuTree.root(menuFixture()), visibleRows: 12)
    t.equal(menu.handle(.backspace), .ignored,
            "an empty query at the root has nothing to do — only ESC dismisses")

    _ = menu.handle(.character("s"))
    _ = menu.handle(.character("t"))
    t.equal(menu.handle(.backspace), .redraw, "with a query it deletes")
    t.equal(menu.query, "s", "one character at a time")

    for c in "tyle" { _ = menu.handle(.character(c)) }
    _ = menu.handle(.enter)
    t.equal(menu.depth, 1, "inside Style")
    t.equal(menu.handle(.backspace), .redraw, "an empty query in a submenu")
    t.equal(menu.depth, 0, "pops back out")
}

h.test("ENTER performs an action, and cannot perform what is not there") { t in
    var menu = MenuState(root: MenuTree.root(menuFixture()), visibleRows: 12)
    for c in "workspaces" { _ = menu.handle(.character(c)) }
    _ = menu.handle(.enter)
    for c in "workspace 7" { _ = menu.handle(.character(c)) }
    t.equal(menu.handle(.enter), .perform(.command(.workspace(.index(7)))),
            "the row dispatches through the same command a hotkey would")

    var empty = MenuState(root: MenuTree.root(menuFixture()), visibleRows: 12)
    for c in "zzzz" { _ = empty.handle(.character(c)) }
    t.equal(empty.rows.count, 0, "nothing matches")
    t.equal(empty.handle(.enter), .ignored, "so ENTER does nothing")
    t.equal(empty.handle(.down), .ignored, "and neither does moving")

    var info = MenuState(root: MenuEntry(id: "root", title: "Go",
                                         kind: .submenu([.info("i", "No windows")])),
                         visibleRows: 12)
    t.equal(info.handle(.enter), .ignored, "a label is not activatable")
}

h.test("TAB descends but never fires an action") { t in
    var menu = MenuState(root: MenuTree.root(menuFixture()), visibleRows: 12)
    for c in "system" { _ = menu.handle(.character(c)) }
    t.equal(menu.handle(.tab), .redraw, "TAB into a submenu")
    t.equal(menu.depth, 1, "descends")
    t.equal(menu.handle(.tab), .ignored,
            "but on an action it does nothing — reaching for it must never restart your Mac")
}

h.test("CTRL+W and CTRL+U clear the query") { t in
    var menu = MenuState(root: MenuTree.root(menuFixture()), visibleRows: 12)
    for c in "sty le" { _ = menu.handle(.character(c)) }
    t.equal(menu.handle(.deleteWord), .redraw, "delete a word")
    t.equal(menu.query, "sty ", "back to the previous one")
    t.equal(menu.handle(.clearLine), .redraw, "clear the line")
    t.equal(menu.query, "", "all of it")
    t.equal(menu.handle(.clearLine), .ignored, "and again does nothing")
}

h.test("the panel keeps walker's geometry") { t in
    t.equal(QuickMenuGeometry.width, 295, "walker's --width")
    t.equal(QuickMenuGeometry.height(rowCount: 100), 630, "clamped to walker's --maxheight")
    t.equal(QuickMenuGeometry.height(rowCount: 0), QuickMenuGeometry.chrome,
            "and an empty list is just the prompt")
    t.equal(QuickMenuGeometry.height(rowCount: 3),
            QuickMenuGeometry.chrome + 3 * QuickMenuGeometry.rowHeight, "three rows deep")
    t.expect(QuickMenuGeometry.visibleRows() >= 18, "630pt holds a useful number of rows")

    let screen = box(0, 0, 1512, 900)
    let frame = QuickMenuGeometry.frame(rowCount: 5, on: screen)
    t.equal(frame.w, 295, "the panel is walker's width")
    t.equal(frame.x, ((1512 - 295) / 2).rounded(), "horizontally centred")
    t.expect(frame.y > 0 && frame.maxY < 900, "and sits on the screen, a little above centre")

    let narrow = QuickMenuGeometry.frame(rowCount: 5, on: box(0, 0, 200, 900))
    t.equal(narrow.w, 200, "never wider than the display it is on")
}

h.test("TOMLEdit replaces a value and leaves the file otherwise alone") { t in
    let before = """
    # toe
    [border]
    enabled      = true
    width        = 2
    active_start = "#33ccffee"   # the gradient's first stop
    active_end   = "#00ff99ee"
    angle        = 45

    [[float]]
    app = "com.apple.finder"
    """
    let after = TOMLEdit.apply([
        .init(table: "border", key: "active_start", value: .string("#7aa2f7ee")),
        .init(table: "border", key: "active_end", value: .string("#bb9af7ee")),
    ], to: before)

    t.expect(after.contains("active_start = \"#7aa2f7ee\"   # the gradient's first stop"),
             "the value changes, the alignment and the comment do not")
    t.expect(after.contains("active_end   = \"#bb9af7ee\""), "and the column is kept")
    t.expect(after.contains("# toe"), "the header comment survives")
    t.expect(after.contains("width        = 2"), "untouched keys are untouched")
    t.expect(after.contains("app = \"com.apple.finder\""), "and so is the float rule")

    let parsed = try Config.parse(after)
    t.equal(parsed.border.activeStart, "#7aa2f7ee", "and it parses back to the new theme")
    t.equal(parsed.border.activeEnd, "#bb9af7ee", "both stops")
    t.equal(parsed.border.width, 2, "with everything else intact")
}

h.test("TOMLEdit inserts a missing key inside its own section") { t in
    let before = """
    [border]
    enabled = true

    [bar]
    persistent_workspaces = 5
    """
    let after = TOMLEdit.apply([
        .init(table: "border", key: "active_start", value: .string("#7aa2f7ee")),
    ], to: before)

    let lines = after.components(separatedBy: "\n")
    let inserted = lines.firstIndex { $0.contains("active_start") }
    let barHeader = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[bar]" }
    t.expect(inserted != nil, "the key is added")
    t.expect((inserted ?? 99) < (barHeader ?? 0),
             "above the next section header, not at the end of the file")
    t.equal(try Config.parse(after).border.activeStart, "#7aa2f7ee", "and it takes effect")
}

h.test("TOMLEdit appends a section that is not there at all") { t in
    let after = TOMLEdit.apply([
        .init(table: "border", key: "active_start", value: .string("#7aa2f7ee")),
        .init(table: "border", key: "active_end", value: .string("#bb9af7ee")),
    ], to: "[general]\nsuper_key = \"alt\"\n")
    t.expect(after.contains("[border]"), "the section is created")
    let parsed = try Config.parse(after)
    t.equal(parsed.border.activeStart, "#7aa2f7ee", "and read back")
    t.equal(parsed.superKey, Modifiers.option, "without disturbing what was there")
}

h.test("TOMLEdit is not fooled by lookalike headers") { t in
    let before = """
    # A [border] mentioned in a comment is not a section.
    [general]
    note = "see [border] below"
    gaps_in = 5

    [[float]]
    app = "com.apple.finder"

    [border]
    active_start = "#33ccffee"
    """
    let after = TOMLEdit.apply([
        .init(table: "border", key: "active_start", value: .string("#7aa2f7ee")),
    ], to: before)

    t.expect(after.contains("note = \"see [border] below\""),
             "a header inside a string is left alone")
    t.expect(after.contains("# A [border] mentioned in a comment is not a section."),
             "and so is one inside a comment")
    t.expect(after.contains("active_start = \"#7aa2f7ee\""), "the real section is edited")
    t.expect(!after.contains("#33ccffee"), "exactly once")
    t.equal(after.components(separatedBy: "active_start").count - 1, 1,
            "and no duplicate key is inserted")
}

h.test("TOMLEdit writes ints, floats and bools, and is idempotent") { t in
    let before = "[general]\ngaps_in  = 5\ngaps_out = 10\n\n[border]\nenabled = true\n"
    let once = TOMLEdit.apply([
        .init(table: "general", key: "gaps_in", value: .int(10)),
        .init(table: "general", key: "gaps_out", value: .int(20)),
        .init(table: "border", key: "enabled", value: .bool(false)),
    ], to: before)
    let twice = TOMLEdit.apply([
        .init(table: "general", key: "gaps_in", value: .int(10)),
        .init(table: "general", key: "gaps_out", value: .int(20)),
        .init(table: "border", key: "enabled", value: .bool(false)),
    ], to: once)
    t.equal(once, twice, "applying the same edit twice changes nothing the second time")

    let parsed = try Config.parse(once)
    t.equal(parsed.gaps.inner, 10, "gaps_in")
    t.equal(parsed.gaps.outer, 20, "gaps_out")
    t.equal(parsed.border.enabled, false, "and a bool")

    let floated = TOMLEdit.apply([
        .init(table: "dwindle", key: "default_split_ratio", value: .double(1.0)),
    ], to: "[dwindle]\ndefault_split_ratio = 0.5\n")
    t.expect(floated.contains("= 1.0"), "a whole float still reads as a float")
}

h.test("the shipped default config survives a theme apply intact") { t in
    let after = TOMLEdit.apply([
        .init(table: "border", key: "active_start", value: .string("#88c0d0ee")),
        .init(table: "border", key: "active_end", value: .string("#5e81acee")),
    ], to: Config.defaultTOML)

    let beforeLines = Config.defaultTOML.components(separatedBy: "\n")
    let afterLines = after.components(separatedBy: "\n")
    t.equal(afterLines.count, beforeLines.count, "no lines added or removed")
    let changed = zip(beforeLines, afterLines).filter { $0 != $1 }
    t.equal(changed.count, 2, "exactly the two lines the theme touches")

    let config = try Config.parse(after)
    t.equal(BorderTheme.matching(config.border)?.id, .some("nord"), "and the menu ticks Nord")
    t.equal(config.bindings.count, try Config.parse(Config.defaultTOML).bindings.count,
            "with every binding still bound")
}
h.test("RGBA parses the spellings Hyprland writes") { t in
    t.equal(RGBA.parse(hex: "#33ccffee"), .some(RGBA(r: 0x33 / 255, g: 0xcc / 255,
                                                     b: 0xff / 255, a: 0xee / 255)),
            "#RRGGBBAA, Hyprland's rgba() ordering")
    t.equal(RGBA.parse(hex: "#33ccff")?.a, .some(1.0), "#RRGGBB is opaque")
    t.equal(RGBA.parse(hex: "0x33ccff"), RGBA.parse(hex: "#33ccff"), "0x is accepted too")
    t.equal(RGBA.parse(hex: "  #33CCFF  "), RGBA.parse(hex: "#33ccff"),
            "as is whitespace and upper case")
    t.expect(RGBA.parse(hex: "#33cc") == nil, "a wrong-length value is nil, not a guess")
    t.expect(RGBA.parse(hex: "#zzzzzz") == nil, "and so is a non-hex one")
    t.equal(RGBA.parse(hex: "#33ccffee")?.withAlpha(0.18).a, .some(0.18), "alpha can be replaced")
}

exit(h.report())
