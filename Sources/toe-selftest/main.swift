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
    t.equal(wm.isFloating(2), true, "the second press keeps w2 floating")
    t.equalBox(wm.render().floating[2], box(151, 49, 1210, 884),
               "re-centred at the larger size, 80% wide by 90% tall")

    wm.toggleFloating(2)
    t.equal(wm.isFloating(2), false, "and the third press tiles it again")
    t.equalBox(wm.workspaces[1]?.layout.idealBox(of: 1), box(0, 0, 756, 982), "w1 back to the left half")
    t.equalBox(wm.workspaces[1]?.layout.idealBox(of: 2), box(756, 0, 756, 982), "w2 back to the right half")
    t.equal(wm.render().floating.isEmpty, true, "nothing floats any more")
}

h.test("togglefloating cycles through both floating sizes before it tiles") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.noteFocus(2)

    wm.toggleFloating(2)
    t.equalBox(wm.render().floating[2], box(227, 98, 1058, 786), "first press: 70% by 80%")
    wm.toggleFloating(2)
    t.equalBox(wm.render().floating[2], box(151, 49, 1210, 884), "second press: 80% by 90%")
    wm.toggleFloating(2)
    t.equal(wm.isFloating(2), false, "third press: back in the tree")
    wm.toggleFloating(2)
    t.equalBox(wm.render().floating[2], box(227, 98, 1058, 786),
               "and round again from the first size")

    // Both sizes are the config's, and setting them the same is the old two-state toggle.
    wm.floatingSize.largeWidth = 0.70
    wm.floatingSize.largeHeight = 0.80
    wm.toggleFloating(2)
    t.equalBox(wm.render().floating[2], box(227, 98, 1058, 786), "the second size can be the first")

    // A window the app layer floated of its own accord never had a size from toe, so the
    // first press tiles it rather than resizing it.
    wm.addWindow(3, floating: true)
    wm.floatingFrames[3] = box(200, 150, 640, 400)
    wm.noteFocus(3)
    wm.toggleFloating(3)
    t.equal(wm.isFloating(3), false, "an adopted floating window tiles on the first press")
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
    // Right round the cycle — larger, tiled, floating again — to re-centre at the first size.
    wm.toggleFloating(2); wm.toggleFloating(2); wm.toggleFloating(2)
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

h.test("movefocus reaches a window togglefloating detached from the grid") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2); wm.addWindow(3)
    wm.noteFocus(3)
    wm.toggleFloating(3)                    // super+t: w3 leaves the tree, centred over w1|w2

    t.equal(wm.isFloating(3), true, "w3 floats")
    t.equal(wm.windowInDirection(.right, from: 1), 3,
            "w3 is centred between the two tiles, so it is what lies to w1's right")
    t.equal(wm.windowInDirection(.left, from: 2), 3, "and to w2's left")
    t.equal(wm.windowInDirection(.left, from: 3), 1, "from the float, the grid is reachable again")
    t.equal(wm.windowInDirection(.right, from: 3), 2, "in both directions")
}

h.test("movefocus reaches a floating window stacked over the only tile left") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.noteFocus(2)
    wm.toggleFloating(2)                    // w1 now fills the display, w2 floats over it

    t.equal(wm.windowInDirection(.right, from: 1), 2,
            "the two centres are one point, so no direction holds w2 — it answers anyway")
    t.equal(wm.windowInDirection(.left, from: 2), 1, "and hands focus back")
}

h.test("a floating window never outranks the tile a grid step points at") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.addWindow(3, floating: true)
    wm.floatingFrames[3] = box(1300, 391, 200, 200)   // tucked against the right edge
    wm.noteFocus(3)

    t.equal(wm.windowInDirection(.right, from: 1), 2,
            "w2's centre is nearer than the float's, recent focus notwithstanding")
    t.equal(wm.windowInDirection(.right, from: 2), 3, "past the last tile, the float is there")
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

h.test("the second floating size is configurable, and a bad one warns") { t in
    let c = try Config.parse("[floating]\nlarge_width = 0.5\nlarge_height = 0.6\n")
    t.equal(c.floating.largeWidth, 0.5, "large_width is read")
    t.equal(c.floating.largeHeight, 0.6, "large_height is read")
    t.equal(c.warnings, [], "no warnings for a fraction in range")

    let bad = try Config.parse("[floating]\nlarge_height = 1.4\n")
    t.equal(bad.floating.largeHeight, 0.90, "out of range keeps the default")
    t.equal(bad.warnings.contains { $0.contains("floating.large_height") }, true, "and says so")
}

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
    t.equal(c.floating.largeWidth, 0.80, "the cycle's second width fraction")
    t.equal(c.floating.largeHeight, 0.90, "the cycle's second height fraction")
    t.equal(c.floating.maxAspectRatio, 1.6, "floating max aspect ratio")
    t.equal(c.gestures.swallowDockSwipes, true, "dock swipes are swallowed by default")
    t.equal(c.misc.disableExposeShortcuts, true, "Ctrl+Up and Ctrl+Down are disabled by default")
    t.equal(c.misc.preventHiding, true, "hiding is undone by default")

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

    // Everything the menu bar item used to offer, now that it offers nothing.
    t.equal(binding("super-comma")?.command, .editConfig, "SUPER+, edits the config")
    t.equal(binding("super-shift-r")?.command, .reload, "SUPER+SHIFT+R reloads it")
    t.equal(binding("super-shift-q")?.command, .quit, "SUPER+SHIFT+Q quits toe")

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

h.test("dock swipe swallowing is configurable") { t in
    let off = try Config.parse("[gestures]\nswallow_dock_swipes = false\n")
    t.equal(off.gestures.swallowDockSwipes, false, "false hands the gestures back to macOS")
    t.equal(off.warnings, [], "no warnings")

    let absent = try Config.parse("[general]\ngaps_in = 5\n")
    t.equal(absent.gestures.swallowDockSwipes, true, "omitting the table keeps the default")

    let bad = try Config.parse("[gestures]\nswallow_dock_swipes = \"yes\"\n")
    t.equal(bad.gestures.swallowDockSwipes, true, "a non-boolean keeps the default")
    t.equal(bad.warnings.contains { $0.contains("gestures.swallow_dock_swipes") }, true,
            "and says so in the menu bar")
}

h.test("the macOS behaviours toe takes over are configurable") { t in
    let off = try Config.parse("[misc]\ndisable_expose_shortcuts = false\nprevent_hiding = false\n")
    t.equal(off.misc.disableExposeShortcuts, false, "the Exposé shortcuts can be handed back")
    t.equal(off.misc.preventHiding, false, "hiding can be allowed")
    t.equal(off.warnings, [], "no warnings")

    let absent = try Config.parse("[general]\ngaps_in = 5\n")
    t.equal(absent.misc.disableExposeShortcuts, true, "omitting the table keeps the defaults")
    t.equal(absent.misc.preventHiding, true, "omitting the table keeps the defaults")

    let bad = try Config.parse("[misc]\nprevent_hiding = 1\n")
    t.equal(bad.misc.preventHiding, true, "a non-boolean keeps the default")
    t.equal(bad.warnings.contains { $0.contains("misc.prevent_hiding") }, true,
            "and says so in the menu bar")
}

h.test("restoring the layout across a restart is configurable") { t in
    let absent = try Config.parse("[general]\ngaps_in = 5\n")
    t.equal(absent.misc.restoreSession, true, "on by default: a restart should cost you nothing")

    let off = try Config.parse("[misc]\nrestore_session = false\n")
    t.equal(off.misc.restoreSession, false, "and can be turned off to keep toe off disk")
    t.equal(off.warnings, [], "no warnings")

    let bad = try Config.parse("[misc]\nrestore_session = \"yes\"\n")
    t.equal(bad.misc.restoreSession, true, "a non-boolean keeps the default")
    t.equal(bad.warnings.contains { $0.contains("misc.restore_session") }, true,
            "and says so in the menu bar")
}

h.test("the escape hatches are bound even when the config forgets them") { t in
    func binding(_ c: Config, _ command: Command) -> Binding? {
        c.bindings.first { $0.command == command }
    }

    // The case that prompted this: a config written before these bindings existed. It is never
    // rewritten, so without a fallback there is no way to quit toe but `pkill`.
    let old = try Config.parse("[binds]\n\"super-w\" = \"killactive\"\n")
    t.equal(binding(old, .quit)?.source, "super-shift-q", "quit is bound")
    t.equal(binding(old, .editConfig)?.source, "super-comma", "editconfig is bound")
    t.equal(binding(old, .reload)?.source, "super-shift-r", "reload is bound")
    t.equal(old.warnings, [], "silently, with no warnings")

    // Your binding wins, and does not also collect the default.
    let rebound = try Config.parse("[binds]\n\"super-shift-x\" = \"quit\"\n")
    t.equal(binding(rebound, .quit)?.source, "super-shift-x", "a rebound quit keeps your key")
    t.equal(rebound.bindings.filter { $0.command == .quit }.count, 1, "and is not bound twice")

    // A fallback whose combination you already used for something else is dropped, not
    // registered on top of yours — the system would refuse the duplicate anyway.
    let clash = try Config.parse("[binds]\n\"super-comma\" = \"killactive\"\n")
    t.equal(binding(clash, .editConfig), nil, "a taken fallback key is left alone")
    t.equal(binding(clash, .killActive)?.source, "super-comma", "and stays yours")
    t.equal(binding(clash, .quit)?.source, "super-shift-q", "the others still land")

    // The shipped config binds all three itself, so nothing should be duplicated.
    let shipped = try Config.parse(Config.defaultTOML)
    for command in [Command.quit, .editConfig, .reload] {
        t.equal(shipped.bindings.filter { $0.command == command }.count, 1,
                "the shipped config binds \(command) exactly once")
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

// The decision is tested here; the window-list read that feeds it lives in WindowStack and
// needs a live window server, so it is not. Geometry from the capture that found the bug:
// Ghostty focused at 15,48 842x1054 with a 4pt band, Raycast's Settings at 364,215 1000x626.
h.test("the border only gives way to a window that covers the band") { t in
    let window = box(15, 48, 842, 1054)
    let width = 4.0
    func covered(_ others: [Box]) -> Bool {
        BorderGeometry.bandIsCovered(window: window, width: width, by: others)
    }

    t.equalBox(BorderGeometry.outset(window, by: width), box(11, 44, 850, 1062),
               "the band's outer rectangle is the panel toe actually put on screen")

    t.equal(covered([box(364, 215, 1000, 626)]), true,
            "a dialog running past the window's right edge covers the band")
    t.equal(covered([box(300, 300, 200, 150)]), false,
            "a dialog centred on the window covers the hole, not the ring")
    t.equal(covered([window]), false,
            "a window the same size and place covers the hole, not the ring")
    t.equal(covered([box(600, 300, 257, 150)]), false,
            "flush against the window's right edge from inside is still the hole")
    t.equal(covered([box(857, 48, 400, 1054)]), true,
            "starting on that edge covers the whole band width")

    t.equal(covered([box(861, 44, 400, 1062)]), false,
            "a neighbouring tile that only abuts the outer rectangle does not count")
    // Measured by how far the overlap reaches *past* the window's edge, so these two differ
    // by where they end, not where they start.
    t.equal(covered([box(600, 300, 257.25, 150)]), false,
            "a quarter-point past the edge is rounding noise between AX and the window server")
    t.equal(covered([box(600, 300, 259, 150)]), true,
            "two points past it is real")

    t.equal(covered([box(15, 900, 842, 300)]), true,
            "poking past the bottom edge covers the band there")
    t.equal(covered([box(0, 0, 3456, 2234)]), true, "a full-screen window covers everything")
    t.equal(covered([box(2000, 48, 800, 1000)]), false,
            "a window on the next display along cannot cover this band")
    t.equal(covered([box(-900, 48, 800, 1000)]), false,
            "nor one on the display to the left, at negative coordinates")

    t.equal(covered([]), false, "nothing above means nothing covering")
    t.equal(BorderGeometry.bandIsCovered(window: window, width: 0, by: [box(0, 0, 3456, 2234)]),
            false, "no band, nothing to cover")

    t.equal(covered([box(300, 300, 200, 150), box(364, 215, 1000, 626)]), true,
            "the second of two is enough")
    t.equal(covered([box(300, 300, 200, 150), box(400, 400, 100, 100)]), false,
            "neither of two is still nothing")
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
    // Asserted by source rather than by count: the escape hatches are bound in code when the
    // config does not bind them, so this config yields its own one good binding plus those.
    t.equal(c.bindings.contains { $0.source == "super-left" }, true, "the one good binding survives")
    t.equal(c.bindings.contains { ["super-nope", "super-h", "super-j"].contains($0.source) }, false,
            "and the three bad ones do not")
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

h.test("a config saved with CRLF line endings parses like any other") { t in
    let crlf = "[general]\r\ngaps_in = 5\r\nsuper_key = \"cmd\"\r\n\r\n[dwindle]\r\nsmart_split = true\r\n"
    let root = try TOML.parse(crlf)

    t.equal(root["general"]?.tableValue?["gaps_in"]?.doubleValue, 5, "an integer stops at the CRLF")
    t.equal(root["general"]?.tableValue?["super_key"]?.stringValue, "cmd", "a string survives")
    t.equal(root["dwindle"]?.tableValue?["smart_split"]?.boolValue, true, "a later header is still found")

    let c = try Config.parse(crlf)
    t.equal(c.gaps.inner, 5, "and the whole config loads rather than falling back")
    t.equal(c.warnings, [], "with no warnings")

    do {
        _ = try TOML.parse("[general]\r\ngaps_in = 5\r\ngaps_out\r\n")
        t.expect(false, "should have thrown")
    } catch let e as TOMLError {
        t.equal(e.line, 3, "and errors still point at the real line, not line 1")
    }
}

h.test("deeply nested values are capped instead of overflowing the stack") { t in
    let deep = 60
    let nested = try TOML.parse("a = " + String(repeating: "[", count: deep) + String(repeating: "]", count: deep))
    t.equal(nested["a"] != nil, true, "\(deep) levels still parse")

    do {
        _ = try TOML.parse("a = " + String(repeating: "[", count: 100_000))
        t.expect(false, "should have thrown")
    } catch let e as TOMLError {
        t.equal(e.message.contains("nested more than"), true, "arrays report the depth limit")
    }

    do {
        _ = try TOML.parse("a = " + String(repeating: "{ b = ", count: 100_000))
        t.expect(false, "should have thrown")
    } catch let e as TOMLError {
        t.equal(e.message.contains("nested more than"), true, "inline tables report it too")
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

// MARK: - Session

/// Round-trips a snapshot through JSON, so the tests below exercise what actually lands on
/// disk rather than an in-memory copy of the structs.
func reencode(_ snapshot: SessionSnapshot) throws -> SessionSnapshot {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SessionSnapshot.self, from: encoder.encode(snapshot))
}

h.test("a restart puts every window back in its own tile") { t in
    let wm = WorkspaceManager()
    wm.options = omarchyLayout().options
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.switchTo(workspace: 1)
    wm.addWindow(1); wm.addWindow(2); wm.addWindow(3); wm.addWindow(4)
    // Not the shape a plain re-insertion would rebuild: a flipped split and an uneven ratio.
    wm.workspaces[1]?.layout.toggleSplit(4)
    wm.workspaces[1]?.layout.alterSplitRatio(3, by: 0.4)
    let before = wm.render().frames

    let snapshot = try reencode(wm.snapshot(boot: "b", monitorKey: { "monitor-\($0)" }))

    let restored = WorkspaceManager()
    restored.options = wm.options
    restored.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    restored.restore(snapshot, monitorID: { $0 == "monitor-1" ? 1 : nil })

    t.equal(restored.render().frames, before, "every tile is where it was, splits and ratios included")
    t.equal(restored.focusedWindow, wm.focusedWindow, "and the same window still has focus")
}

h.test("a restart keeps windows on their own workspaces and monitors") { t in
    let left = box(0, 0, 1512, 982)
    let right = box(1512, 0, 1920, 1080)
    let monitors = [Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)]
    let wm = WorkspaceManager()
    wm.setMonitors(monitors)

    wm.switchTo(workspace: 3)
    wm.addWindow(1); wm.addWindow(2)
    wm.switchTo(workspace: 7)              // hidden once we leave it
    wm.addWindow(3)
    wm.switchTo(workspace: 3)
    wm.toggleFloating(2)
    wm.floatingFrames[2] = box(100, 100, 400, 300)

    let keys = { (id: UInt32) -> String? in "monitor-\(id)" }
    let snapshot = try reencode(wm.snapshot(boot: "b", monitorKey: keys))

    let restored = WorkspaceManager()
    restored.setMonitors(monitors)
    restored.restore(snapshot, monitorID: { UInt32($0.dropFirst("monitor-".count)) })

    t.equal(restored.workspaceIndex(of: 1), 3, "w1 is back on workspace 3")
    t.equal(restored.workspaceIndex(of: 3), 7, "w3 is back on the workspace nothing is showing")
    t.equal(restored.isFloating(2), true, "w2 is still floating")
    t.equalBox(restored.render().floating[2], box(100, 100, 400, 300), "at the frame it was left at")
    restored.toggleFloating(2)
    t.equal(restored.isFloating(2), true,
            "and at the first stage of the cycle, so the next press grows it rather than tiling it")
    t.equal(restored.render().stashed, [3], "and the hidden workspace is still hidden")
    t.equal(restored.activeWorkspace, wm.activeWorkspace, "each monitor shows what it showed")
    t.equal(restored.focusedMonitorID, wm.focusedMonitorID, "on the monitor that had focus")
}

h.test("windows that never came back are dropped, and the tree closes over them") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2); wm.addWindow(3)

    let snapshot = try reencode(wm.snapshot(boot: "b", monitorKey: { "m\($0)" }))
    let restored = WorkspaceManager()
    restored.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    restored.restore(snapshot, monitorID: { _ in 1 })

    // w2's application was quit while toe was down; w1 and w3 are still running.
    t.equal(restored.reap(keeping: [1, 3]), true, "something was dropped")
    t.equal(restored.workspaceIndex(of: 2), nil, "w2 is gone")
    t.equal(restored.focusHistory.contains(2), false, "and out of the focus history")

    // Exactly the layout you would have had if w2 had closed while toe was watching.
    let live = WorkspaceManager()
    live.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    live.addWindow(1); live.addWindow(2); live.addWindow(3)
    live.removeWindow(2)
    t.equal(restored.render().frames, live.render().frames, "the tree closed over the gap the usual way")

    t.equal(restored.reap(keeping: [1, 3]), false, "nothing left to drop the second time")
}

h.test("a snapshot restored onto a different display reflows into it") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    let snapshot = try reencode(wm.snapshot(boot: "b", monitorKey: { "m\($0)" }))

    // The laptop is now on an external display, and the one the snapshot names is gone.
    let wide = box(0, 0, 3440, 1400)
    let restored = WorkspaceManager()
    restored.setMonitors([Monitor(id: 9, frame: wide, usable: wide)])
    restored.restore(snapshot, monitorID: { _ in nil })

    t.equal(restored.workspaceIndex(of: 1), restored.focusedWorkspaceIndex, "the workspace came home to the focused monitor")
    t.equalBox(restored.render().frames[1], box(10, 10, 1705, 1380), "w1 fills half the new display")
    t.equalBox(restored.render().frames[2], box(1725, 10, 1705, 1380), "w2 the other half")
}

h.test("a damaged snapshot is repaired rather than trusted") { t in
    // A leaf naming a window that already has one, a split that has lost a side, and a
    // nesting depth no real tree reaches. None of it may produce a layout toe cannot walk.
    var deep = NodeSnapshot(window: 5)
    for _ in 0..<200 {
        deep = NodeSnapshot(splitTop: false, splitRatio: 1.0, children: [deep, NodeSnapshot(window: 6)])
    }
    let root = NodeSnapshot(children: [
        NodeSnapshot(children: [NodeSnapshot(window: 1), NodeSnapshot(window: 1)]),  // repeated
        NodeSnapshot(children: [NodeSnapshot(window: 2)]),                           // one side
    ])

    let layout = omarchyLayout()
    layout.restore(LayoutSnapshot(root: root, order: [1, 1, 2, 99]))
    t.equal(Set(layout.windowIDs), [1, 2], "the repeat is dropped, the half split collapses")
    t.equal(layout.windowIDs.count, 2, "and no window is in the tree twice")
    t.equalBox(layout.idealBox(of: 1), box(0, 0, 756, 982), "w1 keeps the left half")
    t.equalBox(layout.idealBox(of: 2), box(756, 0, 756, 982), "w2 takes what is left of the right")

    let deepLayout = omarchyLayout()
    deepLayout.restore(LayoutSnapshot(root: deep, order: []))
    t.equal(deepLayout.windowIDs.isEmpty, false, "a too-deep tree still restores what it can")
    t.equal(deepLayout.windowIDs.count <= NodeSnapshot.maxDepth + 1, true, "and stops descending at the cap")

    // The salvaged tree behaves like any other: a new window splits it, and removal collapses it.
    layout.insert(3, anchor: 1)
    t.equalBox(layout.idealBox(of: 3), box(0, 491, 756, 491), "an insert lands where it should")
    layout.remove(3)
    t.equalBox(layout.idealBox(of: 1), box(0, 0, 756, 982), "and removing it gives the space back")
}

h.test("a snapshot names no monitor it cannot name durably") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1)

    // Whatever the app layer uses to name a display can fail — a monitor pulled between the
    // render and the write. A workspace with no durable home is left out rather than saved
    // against a display id that means nothing next time.
    let snapshot = wm.snapshot(boot: "b", monitorKey: { _ in nil })
    t.equal(snapshot.workspaces.isEmpty, true, "no workspaces written")
    t.equal(snapshot.active.isEmpty, true, "and no monitor claims one")
    t.equal(snapshot.focusedMonitor, nil, "nor is there a focused monitor to point at")
}

// MARK: - Menu bar

h.test("a workspace knows whether it holds anything") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.addWindow(9, floating: true)

    // What the strip asks on every refresh — no window list is ever built for it.
    t.equal(wm.isEmpty(workspace: 1), false, "tiled and floating windows both count")
    t.equal(wm.isEmpty(workspace: 4), true, "an untouched workspace holds nothing")
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

    t.equal(hit(5), nil, "the padding before the strip is not a workspace")
    t.equal(hit(55), nil, "and neither is the padding after it")
    t.equal(WorkspaceStrip.hit(x: 30, widths: [], gap: 7, buttonWidth: 60), nil, "no items, no hit")
}

exit(h.report())
