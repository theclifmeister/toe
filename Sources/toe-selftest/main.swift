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

h.test("workspace next skips the workspaces nothing is on") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])

    wm.addWindow(1)                                   // workspace 1
    wm.switchTo(workspace: 4); wm.addWindow(2)
    wm.switchTo(workspace: 9); wm.addWindow(3)
    wm.switchTo(workspace: 1)

    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, 4, "next is 4, not 2 — 2 and 3 are empty")
    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, 9, "then 9")
    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, 1, "and round to 1")
    wm.switchToRelativeWorkspace(-1)
    t.equal(wm.focusedWorkspaceIndex, 9, "prev walks the same ring backwards")
}

h.test("workspace next stays put when nothing else is in use") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1)

    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, 1, "one workspace in use, so the press does nothing")
}

h.test("workspace next reaches a workspace another monitor is showing") { t in
    let left = box(0, 0, 1512, 982)
    let right = box(1512, 0, 1920, 1080)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)])

    let leftWS = wm.activeWorkspace[1]!
    let rightWS = wm.activeWorkspace[2]!
    wm.switchTo(workspace: leftWS)
    wm.addWindow(1)

    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, rightWS, "the other display's workspace counts, empty or not")
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

/// Two tiles side by side and two detached windows, exactly on top of each other and of
/// different sizes — the arrangement geometry could never separate.
private func listWorkspace() -> WorkspaceManager {
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)                    // left half | right half
    wm.addWindow(3, floating: true); wm.addWindow(4, floating: true)
    wm.floatingFrames[3] = box(227, 98, 1058, 786)
    wm.floatingFrames[4] = box(151, 49, 1211, 885)      // over w3, larger, centres half a point apart
    wm.noteFocus(1)
    return wm
}

h.test("detached windows are a list past the edge of the grid") { t in
    let wm = listWorkspace()

    t.equal(wm.windowInDirection(.right), 2, "the grid first: w2 is the tile to w1's right")
    wm.noteFocus(2)
    t.equal(wm.windowInDirection(.right), 3, "nothing to w2's right on the grid, so the list")
    wm.noteFocus(3)
    t.equal(wm.windowInDirection(.right), 4, "then the next detached window, whatever it looks like")
    wm.noteFocus(4)
    t.equal(wm.windowInDirection(.right), 2,
            "and off the end is back to the tile it came from, so one arrow held down goes round")
    wm.noteFocus(2)
    t.equal(wm.windowInDirection(.right), 3, "round again")
}

h.test("walking the list back is walking it forward, reversed") { t in
    let wm = listWorkspace()
    wm.noteFocus(2); wm.noteFocus(3); wm.noteFocus(4)   // out along the list

    t.equal(wm.windowInDirection(.left), 3, "back down the list")
    wm.noteFocus(3)
    t.equal(wm.windowInDirection(.left), 2, "and out of it, to the tile the focus came from")
    wm.noteFocus(2)
    t.equal(wm.windowInDirection(.left), 1, "the grid again from there")
}

h.test("the list is entered from whichever end the direction arrives at") { t in
    let wm = listWorkspace()

    t.equal(wm.windowInDirection(.left), 4,
            "nothing to the left of the leftmost tile, so the list, from its far end")
    t.equal(wm.windowInDirection(.up), 4, "up is the same walk backwards; down and right forwards")
    wm.noteFocus(4)
    t.equal(wm.windowInDirection(.left), 3, "carrying on the same way")
    wm.noteFocus(3)
    t.equal(wm.windowInDirection(.left), 1, "and out where it came in")
}

h.test("the list is the same walk wherever the detached windows are") { t in
    let wm = listWorkspace()
    // Nothing about the geometry is load-bearing any more: put them in opposite corners and
    // the walk is unchanged, because the order is the order they were opened in.
    wm.floatingFrames[3] = box(1312, 782, 200, 200)     // bottom right
    wm.floatingFrames[4] = box(0, 0, 200, 200)          // top left
    wm.noteFocus(2)

    t.equal(wm.windowInDirection(.right), 3, "the first of the list, though it is the further away")
    wm.noteFocus(3)
    t.equal(wm.windowInDirection(.right), 4, "and on to the second")
    wm.noteFocus(4)
    t.equal(wm.windowInDirection(.left), 3, "the way back is the same list")
}

h.test("a detached window is never a step on the grid") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)
    wm.addWindow(3, floating: true)
    wm.floatingFrames[3] = box(756, 0, 400, 300)     // over w2, sharing w1's right edge
    wm.noteFocus(3)                                  // and the most recently focused window

    t.equal(wm.windowInDirection(.right, from: 1), 2,
            "w3 abuts w1 and was focused more recently, and is still not a step: the grid is tiles")
    t.equal(wm.windowInDirection(.right, from: 2), 3, "it is past the edge of the grid instead")
    t.equal(wm.windowInDirection(.left, from: 3), 2, "and hands the focus back to the tile it came from")
}

h.test("a workspace of nothing but detached windows still walks") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1, floating: true); wm.addWindow(2, floating: true)

    t.equal(wm.windowInDirection(.right, from: 1), 2, "the list is the whole workspace")
    t.equal(wm.windowInDirection(.left, from: 1), nil, "with no tile to come back out to")
    t.equal(wm.windowInDirection(.right, from: 2), nil, "at either end of it")
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

// MARK: - Stacking

h.test("an unfocused float is sunk under the tiles it covers") { t in
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1); wm.addWindow(2)        // left half / right half
    wm.addWindow(3); wm.noteFocus(3)
    wm.toggleFloating(3)                    // w3 floats, centred over both halves
    let plan = wm.render()

    // Focus on the float: it is the window in hand, and nothing moves.
    t.equal(Stacking.raiseOrder(tiles: plan.frames, floats: plan.floating, focused: 3), [],
            "the focused float stays where it is")

    // Focus moves to a tile: both halves come up over the float, the focused one last.
    wm.noteFocus(1)
    t.equal(Stacking.raiseOrder(tiles: plan.frames, floats: plan.floating, focused: 1), [2, 1],
            "the tiles it covers are raised, and the focused tile ends up in front")
    wm.noteFocus(2)
    t.equal(Stacking.raiseOrder(tiles: plan.frames, floats: plan.floating, focused: 2), [1, 2],
            "and the other way round when the focus is on w2")
}

h.test("stacking leaves alone what a float does not cover") { t in
    let tiles: [WindowID: Box] = [1: box(0, 0, 756, 982), 2: box(756, 0, 756, 982)]

    t.equal(Stacking.raiseOrder(tiles: tiles, floats: [:], focused: 1), [],
            "no float, nothing to raise")
    t.equal(Stacking.raiseOrder(tiles: tiles, floats: [3: box(0, 0, 400, 300)], focused: 1),
            [1], "a float over one tile only raises that tile")
    t.equal(Stacking.raiseOrder(tiles: tiles, floats: [3: box(1600, 0, 400, 300)], focused: 1),
            [], "a float over no tile at all — another monitor — raises nothing")
    t.equal(Stacking.raiseOrder(tiles: tiles, floats: [3: box(756, 0, 0, 982)], focused: 1),
            [], "sharing an edge with a tile is not covering it")
}

h.test("a float already at the bottom asks for no raises") { t in
    let tiles: [WindowID: Box] = [1: box(0, 0, 756, 982), 2: box(756, 0, 756, 982)]
    let floats: [WindowID: Box] = [3: box(200, 100, 1000, 700)]   // over both halves

    t.equal(Stacking.raiseOrder(tiles: tiles, floats: floats, focused: 1,
                                stackedAbove: { _ in [1, 2] }), [],
            "both tiles are already above the float, so the stack is left alone")
    t.equal(Stacking.raiseOrder(tiles: tiles, floats: floats, focused: 1,
                                stackedAbove: { _ in [2] }), [2, 1],
            "w1 has come back up over the float — activating its app brings its windows with "
            + "it — so both are raised again")
    t.equal(Stacking.raiseOrder(tiles: tiles, floats: floats, focused: 1,
                                stackedAbove: { _ in [1, 2, 99] }), [],
            "a window toe knows nothing about, above the float, changes none of this")
}

h.test("a focused float is raised back over the tiles under a second one") { t in
    let tiles: [WindowID: Box] = [1: box(0, 0, 1512, 982)]
    let floats: [WindowID: Box] = [2: box(100, 100, 600, 400), 3: box(400, 300, 600, 400)]

    t.equal(Stacking.raiseOrder(tiles: tiles, floats: floats, focused: 2), [1, 2],
            "w3 sinks under the tile, and the focused w2 is raised over it again")
    t.equal(Stacking.raiseOrder(tiles: tiles, floats: floats, focused: nil), [1],
            "with nothing focused the tile is simply lifted over both floats")
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
    t.equal(c.border.radius, -1, "radius follows the window's own corner radius")
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
    t.equal(binding("super-comma")?.command,
            .exec("open -a \"Visual Studio Code\" ~/.config/toe/toe.toml"),
            "SUPER+, opens the config in an editor, as an ordinary exec you can repoint")
    t.equal(binding("super-shift-r")?.command, .reload, "SUPER+SHIFT+R reloads it")
    t.equal(binding("super-shift-q")?.command, .quit, "SUPER+SHIFT+Q quits toe")
    t.equal(binding("super-space")?.command, .menu(.root), "SUPER+SPACE opens the quick menu")
    t.equal(binding("super-space")?.keyCode, 0x31, "space key code")
    t.equal(binding("super-k")?.command, .menu(.keybindings), "SUPER+K lists the bindings")
    t.equal(c.menu.background, "#1a1b26", "the menu ships Omarchy's Tokyo Night background")

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
    let off = try Config.parse("[misc]\ndisable_expose_shortcuts = false\nprevent_hiding = false\ndisable_wallpaper_click = false\n")
    t.equal(off.misc.disableExposeShortcuts, false, "the Exposé shortcuts can be handed back")
    t.equal(off.misc.preventHiding, false, "hiding can be allowed")
    t.equal(off.misc.disableWallpaperClick, false, "the wallpaper click can be handed back")
    t.equal(off.warnings, [], "no warnings")

    let absent = try Config.parse("[general]\ngaps_in = 5\n")
    t.equal(absent.misc.disableExposeShortcuts, true, "omitting the table keeps the defaults")
    t.equal(absent.misc.preventHiding, true, "omitting the table keeps the defaults")
    t.equal(absent.misc.disableWallpaperClick, true, "omitting the table keeps the defaults")

    let bad = try Config.parse("[misc]\nprevent_hiding = 1\ndisable_wallpaper_click = \"no\"\n")
    t.equal(bad.misc.preventHiding, true, "a non-boolean keeps the default")
    t.equal(bad.misc.disableWallpaperClick, true, "a non-boolean keeps the default")
    t.equal(bad.warnings.contains { $0.contains("misc.prevent_hiding") }, true,
            "and says so in the menu bar")
    t.equal(bad.warnings.contains { $0.contains("misc.disable_wallpaper_click") }, true,
            "and says so for the wallpaper click too")
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
    t.equal(binding(old, .reload)?.source, "super-shift-r", "reload is bound")
    t.equal(old.warnings, [], "silently, with no warnings")
    // Opening the config is not on the list: it is an exec of your own now, and a fallback
    // would have to pick an editor for you.
    t.equal(old.bindings.contains { $0.source == "super-comma" }, false,
            "and SUPER+, is left free rather than bound to somebody's editor")

    // Your binding wins, and does not also collect the default.
    let rebound = try Config.parse("[binds]\n\"super-shift-x\" = \"quit\"\n")
    t.equal(binding(rebound, .quit)?.source, "super-shift-x", "a rebound quit keeps your key")
    t.equal(rebound.bindings.filter { $0.command == .quit }.count, 1, "and is not bound twice")

    // A fallback whose combination you already used for something else is dropped, not
    // registered on top of yours — the system would refuse the duplicate anyway.
    let clash = try Config.parse("[binds]\n\"super-shift-q\" = \"killactive\"\n")
    t.equal(binding(clash, .quit), nil, "a taken fallback key is left alone")
    t.equal(binding(clash, .killActive)?.source, "super-shift-q", "and stays yours")
    t.equal(binding(clash, .reload)?.source, "super-shift-r", "the others still land")

    // The shipped config binds both itself, so nothing should be duplicated.
    let shipped = try Config.parse(Config.defaultTOML)
    for command in [Command.quit, .reload] {
        t.equal(shipped.bindings.filter { $0.command == command }.count, 1,
                "the shipped config binds \(command) exactly once")
    }
}

h.test("nan and infinity are refused rather than reaching the layout") { t in
    // TOML spells both, and Double("nan") accepts them. A NaN gap defeats every == in the
    // coordinator: the window is re-written on every render forever, the correction budget
    // never resets, and the NaN is passed to other applications over Accessibility.
    for spelling in ["nan", "inf", "-inf", "+inf"] {
        let c = try Config.parse("[general]\ngaps_in = \(spelling)\n")
        t.equal(c.gaps.inner, 5, "gaps_in = \(spelling) keeps the default")
        t.equal(c.gaps.inner.isFinite, true, "gaps_in = \(spelling) leaves a finite gap")
        t.equal(c.warnings.contains { $0.contains("general.gaps_in") }, true,
                "gaps_in = \(spelling) warns")
    }

    let out = try Config.parse("[general]\ngaps_out = nan\n")
    t.equal(out.gaps.outer, 10, "gaps_out = nan keeps the default")
    t.equal(out.warnings.contains { $0.contains("general.gaps_out") }, true, "and says so")

    let border = try Config.parse("[border]\nwidth = nan\nangle = inf\nradius = nan\n")
    t.equal(border.border.width, 2, "border.width = nan keeps the default")
    t.equal(border.border.angle, 45, "border.angle = inf keeps the default")
    t.equal(border.border.radius, -1, "border.radius = nan keeps the default")
    t.equal(border.warnings.count, 3, "one warning each")

    let dwindle = try Config.parse("[dwindle]\nsplit_width_multiplier = nan\ndefault_split_ratio = inf\n")
    t.equal(dwindle.dwindle.splitWidthMultiplier, 1.0, "split_width_multiplier = nan keeps the default")
    t.equal(dwindle.dwindle.defaultSplitRatio, 1.0, "default_split_ratio = inf keeps the default")
    t.equal(dwindle.warnings.count, 2, "one warning each")
}

h.test("numbers outside a sensible range are refused too") { t in
    // Swift's Double(_: String) takes hex floats, which TOML has no notion of, so this used
    // to parse as a 1024 point gap with no warning at all.
    let hex = try Config.parse("[general]\ngaps_in = 0x1p10\n")
    t.equal(hex.gaps.inner, 5, "a 1024 point gap keeps the default")
    t.equal(hex.warnings.contains { $0.contains("general.gaps_in") }, true, "and says so")

    let negative = try Config.parse("[border]\nwidth = -5\n")
    t.equal(negative.border.width, 2, "a negative border width keeps the default")
    t.equal(negative.warnings.contains { $0.contains("border.width") }, true, "and says so")

    let radius = try Config.parse("[border]\nradius = -2\n")
    t.equal(radius.border.radius, -1, "-1 is the only negative radius, so -2 keeps the default")
    t.equal(radius.warnings.contains { $0.contains("border.radius") }, true, "and says so")

    let ratio = try Config.parse("[dwindle]\ndefault_split_ratio = 5\n")
    t.equal(ratio.dwindle.defaultSplitRatio, 1.0, "a ratio past the clamp keeps the default")
    t.equal(ratio.warnings.contains { $0.contains("dwindle.default_split_ratio") }, true, "and says so")
}

h.test("numbers in range are still read, and warn about nothing") { t in
    let c = try Config.parse("""
    [general]
    gaps_in = 12
    gaps_out = 24
    [border]
    width = 3
    angle = 90
    radius = 8
    [dwindle]
    split_width_multiplier = 1.5
    default_split_ratio = 1.2
    """)
    t.equal(c.gaps, Gaps(inner: 12, outer: 24), "gaps are read")
    t.equal(c.border.width, 3, "border width is read")
    t.equal(c.border.angle, 90, "border angle is read")
    t.equal(c.border.radius, 8, "border radius is read")
    t.equal(c.dwindle.splitWidthMultiplier, 1.5, "split_width_multiplier is read")
    t.equal(c.dwindle.defaultSplitRatio, 1.2, "default_split_ratio is read")
    t.equal(c.warnings, [], "no warnings")
}

h.test("a float where an integer was wanted cannot trap") { t in
    // TOMLValue.intValue truncates a float, and Int(_: Double) traps on a NaN, an infinity
    // or anything past Int's range. Reaching this line at all is the assertion.
    let c = try Config.parse("[dwindle]\nforce_split = nan\nsplit_bias = 1e400\n[bar]\npersistent_workspaces = inf\n")
    t.equal(c.dwindle.forceSplit, 2, "force_split = nan keeps the default")
    t.equal(c.dwindle.splitBias, 0, "split_bias = 1e400 keeps the default")
    t.equal(c.bar.persistentWorkspaces, 5, "persistent_workspaces = inf keeps the default")

    let truncated = try Config.parse("[dwindle]\nforce_split = 1.7\n")
    t.equal(truncated.dwindle.forceSplit, 1, "an ordinary float still truncates toward zero")
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

// The two displays are the built-in Retina panel at the origin and a 2560x1440 external one
// to its right, which is where the coordinates below come from. A fullscreen window fills
// exactly one display, so the fullscreen frames here are the display frames.
h.test("the border gives way only on the display a fullscreen window took over") { t in
    let builtIn = box(0, 0, 1512, 982)
    let external = box(1512, 0, 2560, 1440)
    let tile = box(15, 48, 842, 934)                    // a tile on the built-in display
    func behind(_ fullscreen: Box?) -> Bool {
        BorderGeometry.isBehindFullscreen(window: tile, fullscreen: fullscreen)
    }

    t.equal(behind(nil), false, "nothing is fullscreen, so the border stays")
    t.equal(behind(builtIn), true, "fullscreen on this display covers the tile")
    t.equal(behind(external), false,
            "fullscreen on the other display leaves this one showing its own Space")

    // The regression the display scoping exists for: with `Displays have separate Spaces` both
    // of these are true at once, and a global "is anything fullscreen" flag cannot tell them
    // apart. It answered `true` for both, and took the ring off a tile covering nothing.
    let tileOnExternal = box(1600, 48, 900, 1300)
    t.equal(BorderGeometry.isBehindFullscreen(window: tileOnExternal, fullscreen: external), true,
            "the same fullscreen window does cover a tile on its own display")

    // A window flush against the boundary between the displays. Measured against the window
    // and not the band drawn around it, so the outset cannot bleed onto the neighbour.
    let flush = box(1112, 48, 400, 934)                 // right edge exactly on the boundary
    t.equal(BorderGeometry.isBehindFullscreen(window: flush, fullscreen: external), false,
            "a tile touching the boundary is not on the display across it")
    t.equal(BorderGeometry.isBehindFullscreen(window: flush, fullscreen: builtIn), true,
            "it is on its own display, though")

    // Leaning the same way `bandIsCovered` does: a sliver is AX and the window server
    // disagreeing about an edge, not a shared display.
    t.equal(BorderGeometry.isBehindFullscreen(window: box(1112, 48, 400.5, 934),
                                              fullscreen: external), false,
            "a right edge half a point past the boundary is rounding noise")
    t.equal(BorderGeometry.isBehindFullscreen(window: box(1112, 48, 402, 934),
                                              fullscreen: external), true,
            "two points past it is a window really reaching onto that display")
}

// Guards the reason `activeSpaceChanged` is its own callback rather than `windowStackChanged`.
// `WindowStack.windowsAbove` returns an empty set for a window that is not on screen, and this
// is what `raiseOrder` does with that — so a Space switch that ran the float sink would raise
// the tiles on the Space just left, three times over.
h.test("an off-screen float reads as needing its tiles raised, not as settled") { t in
    let tiles: [WindowID: Box] = [1: box(0, 0, 756, 982), 2: box(756, 0, 756, 982)]
    let floats: [WindowID: Box] = [3: box(300, 200, 900, 500)]   // overlaps both tiles

    // What `WindowStack.windowsAbove` answers for a window on another Space.
    let offScreen = Stacking.raiseOrder(tiles: tiles, floats: floats, focused: 1,
                                        stackedAbove: { _ in [] })
    t.equal(offScreen.isEmpty, false,
            "an empty set reads as 'the float is on top', so the tiles are raised")

    // The same float genuinely at the bottom of what it covers asks for nothing.
    let settled = Stacking.raiseOrder(tiles: tiles, floats: floats, focused: 1,
                                      stackedAbove: { _ in [1, 2] })
    t.equal(settled.isEmpty, true, "a float already under both tiles is left alone")

    // And with no float at all there is nothing to sink either way, which is why this went
    // unnoticed on a layout of pure tiles.
    t.equal(Stacking.raiseOrder(tiles: tiles, floats: [:], focused: 1,
                                stackedAbove: { _ in [] }).isEmpty, true,
            "no floats, no raises")
}

h.test("binding specs parse in both spellings") { t in
    func parse(_ s: String) -> String? {
        guard let (m, code, name) = try? BindingParser.parse(s, superKey: .option) else { return nil }
        return "\(m.description)|\(code)|\(name)"
    }
    t.equal(parse("SUPER SHIFT, LEFT"), parse("super-shift-left"), "Omarchy and dash spellings agree")
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
    func hit(_ x: Double) -> WorkspaceStrip.Hit? {
        WorkspaceStrip.hit(x: x, widths: [8, 8, 8], gap: 7, buttonWidth: 60)
    }
    t.equal(hit(15), .workspace(0), "on the first item")
    t.equal(hit(30), .workspace(1), "on the middle item")
    t.equal(hit(45), .workspace(2), "on the last item")

    // The gaps are not dead: they belong to whichever neighbour is nearer.
    t.equal(hit(21), .workspace(0), "just past the first item")
    t.equal(hit(24), .workspace(1), "just before the second")

    t.equal(hit(5), nil, "the padding before the strip is not a workspace")
    t.equal(hit(55), nil, "and neither is the padding after it")
    t.equal(WorkspaceStrip.hit(x: 30, widths: [], gap: 7, buttonWidth: 60), nil, "no items, no hit")
}

h.test("the mark leads the strip and is its own target") { t in
    // A 10pt mark and its 7pt gap, then three 8pt items 7pt apart, centred in a 78pt button:
    // the mark starts at 11 and the items at 28, 43 and 58.
    func hit(_ x: Double) -> WorkspaceStrip.Hit? {
        WorkspaceStrip.hit(x: x, widths: [8, 8, 8], gap: 7, buttonWidth: 78, leading: 17)
    }
    t.equal(hit(15), .mark, "on the mark")
    t.equal(hit(25), .mark, "and in the gap after it, which is the mark's to keep")
    t.equal(hit(30), .workspace(0), "the first workspace has moved along by the mark's width")
    t.equal(hit(62), .workspace(2), "and so has the last")
    t.equal(hit(5), nil, "the padding before the mark is still nothing")

    t.equal(WorkspaceStrip.hit(x: 34, widths: [], gap: 7, buttonWidth: 60, leading: 17), .mark,
            "with no workspaces on the bar at all, the mark is the whole strip")
    t.equal(WorkspaceStrip.hit(x: 5, widths: [], gap: 7, buttonWidth: 60, leading: 17), nil,
            "and the padding beside it is still nothing")
}

// MARK: - The quick menu

h.test("the filter ranks a prefix above a match buried in the middle") { t in
    let ranked = FuzzyFilter.rank("s", in: ["Setup", "Run on startup"])
    t.equal(ranked.map(\.index), [0, 1], "the prefix comes first, the boundary match second")
    t.expect(ranked[0].score > ranked[1].score, "and it scores higher rather than tying")
}

h.test("an empty query keeps every item in the order it was written") { t in
    let names = ["Setup", "Learn", "Quit"]
    t.equal(FuzzyFilter.rank("", in: names).map(\.index), [0, 1, 2],
            "no query, no reordering — a menu is a menu until you type")
}

h.test("the filter matches a subsequence rather than a substring") { t in
    t.equal(FuzzyFilter.rank("kbnd", in: ["Keybindings"]).map(\.index), [0],
            "letters in order with gaps between them still match, the way walker's does")
    t.equal(FuzzyFilter.rank("dnbk", in: ["Keybindings"]).count, 0,
            "the same letters out of order do not")
    t.equal(FuzzyFilter.rank("zz", in: ["Setup", "Learn"]).count, 0,
            "and what matches nothing is dropped, not merely ranked last")
}

h.test("typing puts the selection back at the top") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    m.move(by: 2)
    t.equal(m.selection, 2, "moved down two")
    m.type("q")
    t.equal(m.selection, 0, "a keystroke re-ranks the list, so the old index means nothing")
    t.equal(m.visible.map(\.title), ["Quit"], "and the list is what was typed")
}

h.test("a submenu is entered, backed out of, and clears the query on the way in") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .on, bindings: []), visibleRows: 10)
    t.equal(m.prompt, "Go…", "walker's placeholder at the root")
    m.type("configure")
    t.equal(m.visible.count, 1, "one row matches 'configure'")
    t.equal(m.activate(), .pushed, "Configure descends rather than dispatching")
    t.equal(m.query, "", "the query does not follow you into the submenu")
    t.equal(m.breadcrumb, ["Configure"], "the level is named")
    t.equal(m.prompt, "Configure…", "and the placeholder says where you are")
    t.equal(m.visible.map(\.title), ["Run on startup"], "what toe can actually change for you")
    t.equal(m.pop(), .popped, "Escape climbs one level")
    t.equal(m.pop(), .closed, "and closes at the root")
}

h.test("backspace eats the query, then leaves the submenu") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    m.type("learn")
    t.equal(m.activate(), .pushed, "into Learn")
    m.type("ke")
    t.equal(m.backspace(), true, "there is a query to eat")
    t.equal(m.backspace(), true, "and one character more")
    t.equal(m.backspace(), false, "an empty query has nothing left — the caller pops")
}

h.test("the filter reads what a row does, not only what it is called") { t in
    let c = try Config.parse(Config.defaultTOML)
    var m = MenuState(root: MenuModel.keybindings(c.bindings, superKey: c.superKey),
                      visibleRows: 40)
    m.type("close")
    t.expect(m.visible.contains { $0.value == "Close window" },
             "on the keybindings page the name is a shortcut, so the description has to match too")
    t.expect(m.visible.allSatisfy { $0.value?.localizedCaseInsensitiveContains("close") == true },
             "and nothing else comes with it")

    var focus = MenuState(root: MenuModel.keybindings(c.bindings, superKey: c.superKey),
                          visibleRows: 40)
    focus.type("focus")
    t.equal(focus.visible.count, 4, "all four arrows, found by what they do")
}

h.test("a name match outranks the same letters found in a description") { t in
    let rows = [["Quit", "Quit toe"], ["Reload the config", "quit nothing"]]
    let ranked = FuzzyFilter.rank("quit", in: rows)
    t.equal(ranked.first?.index, 0, "the row actually called Quit comes first")
    t.equal(ranked.count, 2, "the other still matches rather than being dropped")
}

h.test("an empty field is not a match") { t in
    t.equal(FuzzyFilter.rank("x", in: [["Quit", ""]]).count, 0,
            "a row with no description cannot be found by one")
}

h.test("typing searches the whole tree, not the level in front of you") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    m.type("startup")
    t.equal(m.visible.map(\.title), ["Run on startup"],
            "found two levels down without anyone having to go there")
    t.equal(m.visible.first?.subtitle, "Configure", "and the row says where it lives")
    t.equal(m.activate(), .toggleLoginItem, "acting on it needs no descent either")

    var deep = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    deep.type("keyb")
    t.equal(deep.visible.map(\.title), ["Keybindings"], "the same for the other branch")
    t.equal(deep.visible.first?.subtitle, "Learn", "named by its path")
    t.equal(deep.activate(), .page(.keybindings), "and it still opens the page")
}

h.test("a branch found by searching is still a branch") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    m.type("learn")
    t.equal(m.visible.map(\.title), ["Learn"], "the branch itself matches, not only its children")
    t.equal(m.visible.first?.subtitle, nil, "a row at the level you are on has no path to show")
    t.equal(m.activate(), .pushed, "and it descends the way it does unfiltered")
}

h.test("an empty query is one level at a time, with no paths") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    m.type("z")
    t.equal(m.visible.count, 0, "nothing matches")
    m.backspace()
    t.equal(m.visible.map(\.title), ["Configure", "Learn", "Quit"], "the level comes back")
    t.expect(m.visible.allSatisfy { $0.subtitle == nil },
             "and the paths go away with the search that needed them")
}

h.test("the rows lead where the menu says they do") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    t.equal(m.visible.map(\.title), ["Configure", "Learn", "Quit"], "the whole menu, bare minimum")
    t.equal(m.visible.map(\.leadsOn), [true, true, false], "two lead on, Quit acts")
    m.type("quit")
    t.equal(m.activate(), .run(.quit), "and Quit dispatches rather than descending")

    var learn = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    learn.type("learn")
    _ = learn.activate()
    t.equal(learn.activate(), .page(.keybindings), "Learn holds the keybindings page")
}

h.test("the startup row reads the state it is handed") { t in
    func startup(_ state: LoginItemState) -> MenuItem? {
        let root = MenuModel.root(loginItem: state, bindings: [])
        // By title rather than by position: Configure is the first row only while it is there
        // at all, and the case below is the one where it is not.
        guard case .submenu(let setup)? = root.first(where: { $0.title == "Configure" })?.action
        else { return nil }
        return setup.first
    }
    t.equal(startup(.on)?.value, "on", "the row shows launchd's answer, not a preference")
    t.equal(startup(.on)?.action, .toggleLoginItem, "and pressing it flips it")
    t.equal(startup(.off)?.value, "off", "the other way round")
    t.equal(startup(.unavailable("needs /Applications"))?.title, nil,
            "where it cannot work the row is not there at all — a switch you can see but not "
            + "throw is worse than one you were never offered")
}

h.test("the Edit configuration row is your binding, not toe's idea of an editor") { t in
    func rows(_ toml: String, loginItem: LoginItemState = .off) throws -> [MenuItem] {
        MenuModel.configure(loginItem: loginItem, bindings: try Config.parse(toml).bindings)
    }

    // The shipped config: the row runs exactly the line the file bound, character for character.
    let shipped = try rows(Config.defaultTOML)
    t.equal(shipped.map(\.title), ["Run on startup", "Edit configuration"], "both rows")
    t.equal(shipped.last?.action,
            .run(.exec("open -a \"Visual Studio Code\" ~/.config/toe/toe.toml")),
            "and it opens the config the way your config says to")

    // Point it at another editor and the row follows — nothing here names one.
    let zed = try rows("[binds]\n\"super-comma\" = \"exec open -a Zed ~/.config/toe/toe.toml\"\n")
    t.equal(zed.last?.action, .run(.exec("open -a Zed ~/.config/toe/toe.toml")),
            "the menu opens Zed because the config does")

    // On another key, too: the row is found by what it does, not by where it is bound.
    let moved = try rows("[binds]\n\"super-shift-c\" = \"exec open -e ~/.config/toe/toe.toml\"\n")
    t.equal(moved.last?.action, .run(.exec("open -e ~/.config/toe/toe.toml")),
            "SUPER+SHIFT+C is as good as SUPER+, — the row follows the binding")

    // An exec that opens something else is not an editor for this file.
    let unrelated = try rows("[binds]\n\"super-enter\" = \"exec open -a Ghostty\"\n")
    t.equal(unrelated.map(\.title), ["Run on startup"],
            "no binding that opens the config, no row offering to")
    t.equal(MenuModel.root(loginItem: .unavailable("needs /Applications"),
                           bindings: try Config.parse("[binds]\n\"super-enter\" = \"exec open -a Ghostty\"\n").bindings)
                .map(\.title),
            ["Learn", "Quit"],
            "and with the startup row gone as well, Configure has nothing left to hold")

    // The row is there even when the startup toggle cannot be.
    let buildDir = try rows(Config.defaultTOML, loginItem: .unavailable("needs /Applications"))
    t.equal(buildDir.map(\.title), ["Edit configuration"],
            "the one row that works is still offered")
}

h.test("Configure goes with the startup row, being all that was left in it") { t in
    let m = MenuState(root: MenuModel.root(loginItem: .unavailable("needs /Applications"), bindings: []),
                      visibleRows: 10)
    t.equal(m.visible.map(\.title), ["Learn", "Quit"],
            "a row that leads into an empty level is worse than no row")

    var searching = MenuState(root: MenuModel.root(loginItem: .unavailable("needs /Applications"), bindings: []),
                              visibleRows: 10)
    searching.type("startup")
    t.equal(searching.visible.count, 0, "and the search cannot turn it up either")
}

h.test("the second column never runs into the title") { t in
    let m = MenuMetrics(lineHeight: 22)
    let narrow = MenuLayout.rowFrame(0, width: 295, m)
    // "Run on startup" at 18pt JetBrainsMono, past a 16pt icon and its 14pt gap. The row's x is
    // the content inset, so it is the same at every width and the title ends in the same place.
    let titleEnd = narrow.x + m.itemPaddingLeft + m.iconSide + m.iconGap + 151
    t.equal(MenuLayout.valueSpace(inRow: narrow, titleEnd: titleEnd, m), 28,
            "at walker's 295 there are 28 points for a value that needs 32 to say off — why #74")

    let row = MenuLayout.rowFrame(0, width: MenuConfig().width, m)
    let space = MenuLayout.valueSpace(inRow: row, titleEnd: titleEnd, m)
    t.equal(space, 133, "the 400 the default widened to leaves 133, which off fits inside")
    t.expect(space < 200, "and is still too little to name a reason in, which is why the "
                          + "unavailable startup row is dropped rather than dimmed")

    let wide = MenuLayout.rowFrame(0, width: 800, m)
    t.expect(MenuLayout.valueSpace(inRow: wide, titleEnd: titleEnd, m) > 400,
             "the keybindings page at 800 has room for the whole second column")
    t.equal(MenuLayout.valueSpace(inRow: row, titleEnd: 10_000, m), 0,
            "a title longer than the row leaves nothing rather than a negative width")
}

h.test("the selection clamps at both ends") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, bindings: []), visibleRows: 10)
    m.move(by: -1)
    t.equal(m.selection, 0, "up from the top stays at the top — a list is not a carousel")
    m.move(by: 99)
    t.equal(m.selection, m.visible.count - 1, "and down from the bottom stays at the bottom")
}

h.test("the keybindings page is every binding, in the config's own order") { t in
    let c = try Config.parse(Config.defaultTOML)
    let rows = MenuModel.keybindings(c.bindings, superKey: c.superKey)
    t.equal(rows.count, c.bindings.count, "one row per binding")
    t.expect(rows.first?.value.map { $0.hasPrefix("Move focus") } == true,
             "it opens on the focus keys rather than on SUPER+0, which is where sorting the "
             + "binding strings lands")
    t.expect(rows.allSatisfy { !$0.leadsOn }, "no row on this page leads anywhere else")

    func firstRow(_ predicate: (String) -> Bool) -> Int? { rows.firstIndex { predicate($0.value ?? "") } }
    let workspace = firstRow { $0.hasPrefix("Workspace") }
    let quit = firstRow { $0 == "Quit toe" }
    let launch = firstRow { $0.hasPrefix("Run ") }
    t.expect(workspace ?? 0 < quit ?? 0, "the workspaces come before what toe does to itself")
    t.expect(quit ?? 0 < launch ?? 0, "and the exec bindings are last, being the ones you replace")

    let again = MenuModel.keybindings(c.bindings, superKey: c.superKey)
    t.equal(again.map(\.title), rows.map(\.title), "the order is the same twice running")
}

h.test("shortcuts read the way Omarchy writes them") { t in
    func describe(_ spec: String) throws -> String {
        let (mods, _, name) = try BindingParser.parse(spec, superKey: .option)
        return ShortcutFormatter.describe(modifiers: mods, keyName: name, superKey: .option)
    }
    t.equal(try describe("super-shift-r"), "SUPER + SHIFT + R", "the modifier meaning SUPER prints first")
    t.equal(try describe("super-left"), "SUPER + ←", "arrows are arrows")
    t.equal(try describe("super-comma"), "SUPER + ,", "a named punctuation key is the character it types")
    t.equal(try describe("super-space"), "SUPER + SPACE", "the menu's own binding")
    t.equal(try describe("ctrl-shift-cmd-k"), "CTRL + SHIFT + CMD + K", "a fixed order, however it was typed")
}

h.test("every command has a label a reader could use") { t in
    let all: [Command] = [
        .moveFocus(.left), .swapWindow(.up), .moveWindow(.down),
        .workspace(.index(3)), .workspace(.next), .workspace(.previous), .workspace(.former),
        .moveToWorkspace(5, follow: true), .moveToWorkspace(5, follow: false),
        .killActive, .toggleFloating, .toggleSplit, .swapSplit,
        .exec("open -a Safari"), .reload, .quit,
        .menu(.root), .menu(.keybindings),
    ]
    for command in all {
        let label = CommandLabel.describe(command)
        t.expect(!label.isEmpty, "\(command) has a label")
        t.expect(label.first?.isUppercase == true, "\(command)'s label is prose, not a case name")
    }
    t.equal(CommandLabel.describe(.moveFocus(.left)), "Move focus left", "a sample of the prose")
    t.equal(CommandLabel.describe(.menu(.keybindings)), "Show the keybindings", "and the new one")
}

h.test("the binding that opens the config is named rather than spelled out") { t in
    // It read "Edit the config" while toe owned an `editconfig` command. The label is derived
    // from the line you bound now, so it survives the command's removal without hardcoding one.
    t.equal(CommandLabel.describe(.exec("open -a \"Visual Studio Code\" ~/.config/toe/toe.toml")),
            "Edit the config", "the shipped binding, named")
    t.equal(CommandLabel.describe(.exec("open -a Zed ~/.config/toe/toe.toml")),
            "Edit the config", "and so is yours, whichever editor it names")
    t.equal(CommandLabel.describe(.exec("open -a Ghostty")), "Run open -a Ghostty",
            "an exec that opens something else still shows what it runs")

    // The same rule the menu row is found by, so the two can never disagree.
    let c = try Config.parse(Config.defaultTOML)
    t.equal(MenuModel.configOpener(in: c.bindings)?.source, "super-comma",
            "and it is the binding the menu offers as Edit configuration")
    t.equal(c.bindings.filter { $0.command.opensConfig }.count, 1,
            "exactly one binding in the shipped config opens it")
}

h.test("a long exec line cannot set the width of every row") { t in
    let long = String(repeating: "x", count: 200)
    let label = CommandLabel.describe(.exec(long))
    t.expect(label.count < 60, "cut where the number is visible rather than left to the drawing")
    t.expect(label.hasSuffix("…"), "and said to be cut")
    t.equal(CommandLabel.describe(.exec("open -a Safari")), "Run open -a Safari",
            "a line that fits is left alone")
}

h.test("the panel is as tall as its rows, and never taller than the display") { t in
    let m = MenuMetrics(lineHeight: 22)
    t.equal(MenuLayout.rowHeight(m), 50, "14 above, 22 of text, 14 below — walker's .item-text-box")

    var searching = m
    searching.showsSubtitles = true
    searching.subtitleLineHeight = 16
    t.equal(MenuLayout.rowHeight(searching), 68, "a searched list grows a line for the path")
    t.equal(MenuLayout.subtitleOrigin(inRow: MenuLayout.rowFrame(0, width: 295, searching),
                                      hasIcon: true, searching).y,
            MenuLayout.rowFrame(0, width: 295, searching).y + 14 + 22 + 2,
            "which sits under the title, not beside it")
    t.equal(MenuLayout.chromeHeight(m), 96, "two insets, the search strip and the gap under it")

    let small = MenuLayout.size(rows: 3, width: 295, maxHeight: 900, m)
    t.equal(small.visibleRows, 3, "three rows fit with room to spare")
    t.equal(small.size.y, 246, "and the panel is exactly that tall")
    t.equal(small.size.x, 295, "and as wide as it was asked for")

    let long = MenuLayout.size(rows: 50, width: 800, maxHeight: 900, m)
    t.expect(long.size.y <= 900, "fifty bindings do not make a panel taller than the screen")
    t.equal(long.visibleRows, 16, "it shows as many whole rows as fit")
    t.equal(long.size.y, 896, "and is exactly that tall, with no half row at the bottom")
}

h.test("a click lands on the row under the pointer") { t in
    let m = MenuMetrics(lineHeight: 22)
    t.equal(MenuLayout.row(at: Point(x: 100, y: 79), rows: 3, width: 295, m), 0,
            "just inside the first row")
    t.equal(MenuLayout.row(at: Point(x: 100, y: 129), rows: 3, width: 295, m), 1,
            "and the second")
    t.equal(MenuLayout.row(at: Point(x: 100, y: 5), rows: 3, width: 295, m), nil,
            "the search line is not a row")
    t.equal(MenuLayout.row(at: Point(x: 100, y: 574), rows: 3, width: 295, m), nil,
            "and neither is the space below the last one")
    t.equal(MenuLayout.row(at: Point(x: 5, y: 79), rows: 3, width: 295, m), nil,
            "nor the padding beside it")
}

h.test("scrolling follows the selection by the fewest rows") { t in
    t.equal(MenuLayout.scroll(offset: 0, selection: 3, count: 40, visibleRows: 10), 0,
            "a selection already on screen does not scroll")
    t.equal(MenuLayout.scroll(offset: 0, selection: 12, count: 40, visibleRows: 10), 3,
            "past the bottom scrolls just enough to show it")
    t.equal(MenuLayout.scroll(offset: 20, selection: 4, count: 40, visibleRows: 10), 4,
            "and back up puts it on the first row")
    t.equal(MenuLayout.scroll(offset: 35, selection: 39, count: 40, visibleRows: 10), 30,
            "the last page never scrolls past the end")
    t.equal(MenuLayout.scroll(offset: 0, selection: 2, count: 3, visibleRows: 10), 0,
            "a list that fits never scrolls at all")
}

h.test("the menu is centred on the monitor that has the focus") { t in
    let usable = box(1512, 0, 2560, 1415)              // a second display, to the right
    let frame = MenuLayout.centred(size: Point(x: 295, y: 250), on: usable)
    t.equalBox(frame, box(1512 + (2560 - 295) / 2, (1415 - 250) / 2, 295, 250),
               "dead centre of the usable area, not of the primary display")
}

h.test("hex colours parse in both lengths") { t in
    t.equal(Hex.rgba("#1a1b26"), RGBA(r: 26.0/255, g: 27.0/255, b: 38.0/255, a: 1),
            "Tokyo Night's background, six digits and opaque")
    t.equal(Hex.rgba("#33ccffee")?.a, 238.0/255, "eight digits put the alpha last, as Hyprland does")
    t.equal(Hex.rgba("7AA2F7"), Hex.rgba("#7aa2f7"), "the hash and the case are both optional")
    t.equal(Hex.rgba("#1a1b26")?.withAlpha(0.95).a, 0.95, "and alpha(@base, 0.95) is a method")
}

h.test("a colour that will not parse is nil rather than a guess") { t in
    t.equal(Hex.rgba("blue"), nil, "a name is not a hex colour")
    t.equal(Hex.rgba("#12345"), nil, "and neither is five digits")
    t.equal(Hex.rgba(""), nil, "nor nothing at all")
    t.equal(Hex.rgba("#-2345f"), nil, "nor a sign smuggled into the digits")
}

h.test("the menu table defaults to Omarchy's Tokyo Night") { t in
    let c = try Config.parse("[general]\ngaps_in = 5\n")
    t.equal(c.menu.background, "#1a1b26", "@base")
    t.equal(c.menu.foreground, "#a9b1d6", "@text, which is also @border")
    t.equal(c.menu.accent, "#7aa2f7", "@selected-text")
    t.equal(c.menu.borderColor, c.menu.foreground, "walker maps the border to the foreground")
    t.equal(c.menu.opacity, 0.95, "alpha(@base, 0.95)")
    t.equal(c.menu.width, 400, "wider than omarchy-menu's 295: these rows are sentences")
    t.equal(c.menu.listWidth, 800, "and for a list view")
    t.equal(c.menu.fontSize, 18, "walker draws at 18px")
}

h.test("a nonsense menu colour is named and the default kept") { t in
    let c = try Config.parse("[menu]\nbackground = \"chartreuse\"\nopacity = 4\n")
    t.equal(c.menu.background, "#1a1b26", "the default stands")
    t.equal(c.menu.opacity, 0.95, "and so does the opacity")
    t.equal(c.warnings.count, 2, "both are named rather than swallowed")
    t.expect(c.warnings.contains { $0.contains("menu.background") }, "the colour is named")
    t.expect(c.warnings.contains { $0.contains("menu.opacity") }, "and so is the number")
}

h.test("an explicit menu border overrides walker's mapping") { t in
    let c = try Config.parse("[menu]\nborder = \"#ff0000\"\n")
    t.equal(c.menu.borderColor, "#ff0000", "a value wins over the foreground")
    t.equal(c.warnings, [], "no warnings")
}

h.test("the menu reaches a config written before it existed") { t in
    // No [binds] at all — an upgrade from a version with no menu. A config is never rewritten,
    // so the fallback is the only way SUPER+SPACE ever arrives.
    let c = try Config.parse("[general]\nsuper_key = \"alt\"\n")
    let menu = c.bindings.first { $0.command == .menu(.root) }
    t.expect(menu != nil, "SUPER+SPACE is bound in code")
    t.equal(menu?.keyCode, KeyCodes.code(for: "space"), "to space")
    t.equal(menu?.modifiers, Modifiers.option, "with SUPER resolved to the configured key")
    t.expect(c.bindings.contains { $0.command == .menu(.keybindings) }, "and SUPER+K with it")
}

h.test("a config that binds the menu itself keeps its own key") { t in
    let c = try Config.parse("[binds]\n\"super-slash\" = \"menu\"\n")
    let menus = c.bindings.filter { $0.command == .menu(.root) }
    t.equal(menus.count, 1, "the fallback stands aside for a binding you wrote")
    t.equal(menus.first?.keyName, "slash", "and yours is the one that survives")
}

h.test("menu commands parse in both spellings") { t in
    t.equal(try CommandParser.parse("menu"), .menu(.root), "bare")
    t.equal(try CommandParser.parse("menu, keybindings"), .menu(.keybindings), "Hyprland's comma form")
    t.equal(try CommandParser.parse("menu keybindings"), .menu(.keybindings), "and the plain one")
    t.equal(try CommandParser.parse("keybindings"), .menu(.keybindings), "the shorthand")
    t.equal(try CommandParser.parse("menu keys"), .menu(.keybindings), "and its abbreviation")
    t.expect((try? CommandParser.parse("menu wardrobe")) == nil,
             "an unknown page is an error rather than quietly the root menu")
}

exit(h.report())
