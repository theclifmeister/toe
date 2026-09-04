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

// MARK: - resizeactive

h.test("resizeactive moves the split, whichever side of it the window is on") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    t.equal(l.resizeActive(2, dx: 100, dy: 0, edges: []), true, "from the right-hand window")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 856, 982), "the split went 100 right: w1 grew")
    t.equalBox(l.idealBox(of: 2), box(856, 0, 656, 982), "and w2 shrank — Omarchy's =, not 'grow me'")

    let m = omarchyLayout()
    m.insert(1, anchor: nil)
    m.insert(2, anchor: 1)
    m.resizeActive(1, dx: 100, dy: 0, edges: [])
    t.equalBox(m.idealBox(of: 1), box(0, 0, 856, 982), "the same press from the left-hand window")
    t.equalBox(m.idealBox(of: 2), box(856, 0, 656, 982), "is the same result")

    t.equal(m.resizeActive(1, dx: 0, dy: 50, edges: []), false,
            "a side-by-side pair has no vertical split to move")
    t.equalBox(m.idealBox(of: 1), box(0, 0, 856, 982), "and nothing moved")
    t.equal(m.resizeActive(9, dx: 50, dy: 0, edges: []), false, "a window the tree does not hold")

    let one = omarchyLayout()
    one.insert(1, anchor: nil)
    t.equal(one.resizeActive(1, dx: 50, dy: 50, edges: []), false, "the only window has no split at all")
    t.equalBox(one.idealBox(of: 1), AREA, "and keeps the whole area")
}

h.test("growactive grows the window you are in, whichever side of the split it is on") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    t.equal(l.growActive(2, dx: 100, dy: 0), true, "from the right-hand window")
    t.equalBox(l.idealBox(of: 2), box(656, 0, 856, 982), "w2 grew: the split went *left*")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 656, 982), "at w1's expense")
    t.equal(l.growActive(1, dx: 100, dy: 0), true, "and from the left-hand one")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "w1 grew back: the split went right")
    t.equal(l.growActive(1, dx: 0, dy: 100), false, "no vertical split, nothing to grow into")

    // w1 | (w2 / w3): w3 is the bottom child, so taller means the split above it moving up.
    let m = omarchyLayout()
    m.insert(1, anchor: nil)
    m.insert(2, anchor: 1)
    m.insert(3, anchor: 2)
    m.growActive(3, dx: 0, dy: 50)
    t.equalBox(m.idealBox(of: 3), box(756, 441, 756, 541), "w3 is 50 taller")
    t.equalBox(m.idealBox(of: 2), box(756, 0, 756, 441), "w2 gave it up")
    m.growActive(2, dx: 0, dy: 50)
    t.equalBox(m.idealBox(of: 2), box(756, 0, 756, 491), "and takes it back — the split goes down for w2")
    m.growActive(3, dx: 100, dy: 0)
    t.equalBox(m.idealBox(of: 1), box(0, 0, 656, 982),
               "wider for w3 is the root split moving left, though w3 is not its direct child")
    t.equalBox(m.idealBox(of: 3), box(656, 491, 856, 491), "and w3 has the width")
}

h.test("resizeactive finds the nearest split of each orientation") { t in
    // w1 | (w2 / w3): the vertical axis lives one level down, the horizontal one at the root.
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)
    t.equalBox(l.idealBox(of: 3), box(756, 491, 756, 491), "fixture: w3 under w2")

    t.equal(l.resizeActive(3, dx: 0, dy: -50, edges: []), true, "up")
    t.equalBox(l.idealBox(of: 2), box(756, 0, 756, 441), "the w2/w3 split went 50 up")
    t.equalBox(l.idealBox(of: 3), box(756, 441, 756, 541), "so w3 grew")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 756, 982), "and w1 never noticed")

    let m = omarchyLayout()
    m.insert(1, anchor: nil)
    m.insert(2, anchor: 1)
    m.insert(3, anchor: 2)
    t.equal(m.resizeActive(3, dx: 40, dy: 0, edges: []), true, "right")
    t.equalBox(m.idealBox(of: 1), box(0, 0, 796, 982), "the root split went 40 right")
    t.equalBox(m.idealBox(of: 2), box(796, 0, 716, 491), "w2 gave the width up")
    t.equalBox(m.idealBox(of: 3), box(796, 491, 716, 491), "and so did w3, its height untouched")
}

h.test("pulling an edge keeps the far edge still — Hyprland's smart_resizing") { t in
    // w1 | (w2 | w3) on a wide display, so the second split is side by side too. Pulling
    // w2's left edge outwards has to move the root split *and* re-solve the inner one, or w3
    // would stretch along with everything under that split.
    let l = omarchyLayout(area: box(0, 0, 3000, 600))
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.insert(3, anchor: 2)
    t.equalBox(l.idealBox(of: 2), box(1500, 0, 750, 600), "fixture: w2")
    t.equalBox(l.idealBox(of: 3), box(2250, 0, 750, 600), "fixture: w3")

    t.equal(l.resizeActive(2, dx: -100, dy: 0, edges: [.left]), true, "w2's left edge, 100 outwards")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 1400, 600), "w1 gave up the 100")
    t.equalBox(l.idealBox(of: 2), box(1400, 0, 850, 600), "w2 took it")
    t.equalBox(l.idealBox(of: 3), box(2250, 0, 750, 600), "and w3 is exactly where it was")
}

h.test("an edge on the display's edge pulls the other one, as Hyprland's does") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    // The left edge of the leftmost window cannot move; DISPLAYLEFT turns the pull into a
    // RIGHT one and the split on its other side moves instead. That is what a Super+right-drag
    // does at a screen edge upstream, and it is kept on purpose rather than special-cased.
    t.equal(l.resizeActive(1, dx: 50, dy: 0, edges: [.left]), true, "w1's left edge, 50 inwards")
    t.equalBox(l.idealBox(of: 1), box(0, 0, 806, 982), "the split on its right went 50 right")
    t.equalBox(l.idealBox(of: 2), box(806, 0, 706, 982), "at w2's expense")

    l.toggleSplit(2)
    t.equal(l.resizeActive(2, dx: 50, dy: 0, edges: []), false,
            "a window spanning the full width has no horizontal freedom, and that axis is dropped")
}

h.test("resizeactive clamps at Hyprland's 0.1 … 1.9") { t in
    let l = omarchyLayout()
    l.insert(1, anchor: nil)
    l.insert(2, anchor: 1)
    l.resizeActive(1, dx: 5000, dy: 0, edges: [])
    t.equal(l.node(for: 1)?.parent?.splitRatio, 1.9, "as far right as it goes")
    t.equalBox(l.idealBox(of: 2), box(1436.4, 0, 75.6, 982), "w2 keeps a sliver")
    l.resizeActive(1, dx: -9000, dy: 0, edges: [])
    t.equal(l.node(for: 1)?.parent?.splitRatio, 0.1, "and as far left")
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
    // persistent 0 is the strip with no padding, so the ring is the workspaces in use.
    let wm = WorkspaceManager()
    wm.persistentWorkspaces = 0
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

h.test("workspace next walks the padded slots the strip is showing") { t in
    // The strip you can see is the ring TAB walks: with only 1, 4 and 9 in use the padding
    // puts 2 and 3 on the bar, so a press has to be able to reach them. 5 is not on the bar —
    // the padding stopped at five slots — so a press must not land there either.
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])

    wm.addWindow(1)
    wm.switchTo(workspace: 4); wm.addWindow(2)
    wm.switchTo(workspace: 9); wm.addWindow(3)
    wm.switchTo(workspace: 1)

    t.equal(WorkspaceStrip.slots(for: wm.stripStates(), persistent: 5), [1, 2, 3, 4, 9],
            "two empties pad the strip to five")

    var walked: [Int] = []
    for _ in 1...5 { wm.switchToRelativeWorkspace(1); walked.append(wm.focusedWorkspaceIndex) }
    t.equal(walked, [2, 3, 4, 9, 1], "TAB visits every slot on the bar and rounds")

    wm.switchToRelativeWorkspace(-1)
    t.equal(wm.focusedWorkspaceIndex, 9, "prev walks the same ring backwards")
}

h.test("workspace next stops padding once the strip is full") { t in
    // 1, 2, 3, 5, 6 and 9 in use is already six slots, so no empty workspace joins the ring —
    // and 4, sitting between two busy neighbours, is the one a naive `index <= persistent`
    // used to hand you on the way past.
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])

    var next = WindowID(1)
    for index in [1, 2, 3, 5, 6, 9] {
        wm.switchTo(workspace: index); wm.addWindow(next); next += 1
    }
    wm.switchTo(workspace: 3)

    t.equal(WorkspaceStrip.slots(for: wm.stripStates(), persistent: 5), [1, 2, 3, 5, 6, 9],
            "six in use, so nothing is padded in — 4 included")

    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, 5, "next steps over the empty 4")
}

h.test("workspace next stays put when nothing else is in use") { t in
    let wm = WorkspaceManager()
    wm.persistentWorkspaces = 0
    wm.setMonitors([Monitor(id: 1, frame: AREA, usable: AREA)])
    wm.addWindow(1)

    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, 1, "one workspace in use, so the press does nothing")

    // With Omarchy's five persistent slots there is somewhere to go, even on a fresh session.
    wm.persistentWorkspaces = 5
    wm.switchToRelativeWorkspace(1)
    t.equal(wm.focusedWorkspaceIndex, 2, "the padded slots are reachable from the first press")
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

    // Switching to the other monitor's active workspace moves focus there — to a window on it,
    // not just to the monitor. With a window on each side this used to leave `focusedWindow` on
    // the display the focus was supposed to be leaving: `refocusVisible` picked the most recent
    // window across *every* monitor, and the one you were standing on always won.
    let otherMonitor = wm.monitors.first { $0.id != home }!.id
    let otherWorkspace = wm.activeWorkspace[otherMonitor]!
    wm.switchTo(workspace: otherWorkspace)
    wm.addWindow(2)
    wm.switchTo(workspace: 5)
    t.equal(wm.focusedWindow, 1, "back on workspace 5, its window has the focus")
    wm.switchTo(workspace: otherWorkspace)
    t.equal(wm.focusedMonitorID, otherMonitor, "focus moved to the monitor owning that workspace")
    t.equal(wm.focusedWindow, 2, "and to the window on it, not the one it came from")
    t.equal(wm.render().focus, 2, "which is what the coordinator is told to focus")

    // And coming back to workspace 5 returns to its own monitor.
    wm.switchTo(workspace: 5)
    t.equal(wm.focusedMonitorID, home, "workspace 5 pulled focus back to its monitor")
    t.equal(wm.focusedWindow, 1, "and its window has the focus again")
    t.equal(wm.render().focus, 1, "for the coordinator too")
}

h.test("an empty workspace has no focused window, on either monitor") { t in
    let left = box(0, 0, 1512, 982)
    let right = box(1512, 0, 1920, 1080)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)])
    wm.switchTo(workspace: 2); wm.addWindow(20)       // a window on monitor 2
    wm.switchTo(workspace: 1); wm.addWindow(10)       // a window on monitor 1

    // Bringing an empty workspace up on monitor 1 used to hand the focus to monitor 2's window:
    // `focusedWindow` was the most recent window visible *anywhere*, and with w10 stashed that
    // was w20. Every command then acted on a window on a display the focus had not gone to.
    wm.switchTo(workspace: 5)
    t.equal(wm.focusedMonitorID, 1, "workspace 5 came up on the monitor that asked for it")
    t.equal(wm.focusedWindow, nil, "an empty workspace has nothing to focus")
    t.equal(wm.render().focus, nil, "so the coordinator is told to focus nothing")
    t.equal(wm.windowInDirection(.right), nil, "movefocus has nowhere to start from")
    t.equal(wm.swapWindow(.right), false, "swapwindow has nothing to swap")
    wm.moveFocusedWindow(toWorkspace: 6, follow: false)
    t.equal(wm.workspaceIndex(of: 20), 2, "movetoworkspace did not reach across to w20")

    // Clicking into the other display is a real focus notification, and that still lands.
    wm.noteFocus(20)
    t.equal(wm.focusedMonitorID, 2, "a real focus on w20 moves to its monitor")
    t.equal(wm.focusedWindow, 20, "and w20 is the focused window")

    // The same empty workspace already showing on the *other* monitor: focus goes there and
    // stops, rather than staying on w20.
    wm.switchTo(workspace: 5)
    t.equal(wm.focusedMonitorID, 1, "workspace 5 is on monitor 1, so the focus went there")
    t.equal(wm.focusedWindow, nil, "with nothing on it to focus")
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

// MARK: - Resizing by hand

h.test("a resize gesture names the edge that moved, and how far it went") { t in
    let tile = box(15, 15, 733, 952)
    func d(_ frame: Box) -> (edges: ResizeEdges, dx: Double, dy: Double)? {
        ResizeGesture.delta(from: tile, to: frame)
    }
    t.equal(d(box(15, 15, 833, 952))?.edges, [.right], "the right edge pulled out")
    t.equal(d(box(15, 15, 833, 952))?.dx, 100, "by 100")
    t.equal(d(box(65, 15, 683, 952))?.edges, [.left], "the left edge pulled in: x and w both change")
    t.equal(d(box(65, 15, 683, 952))?.dx, 50, "and the edge went 50 right — not 'the width lost 50'")
    t.equal(d(box(-35, 15, 783, 952))?.dx, -50, "pulled out, the same edge goes left")
    t.equal(d(box(15, 15, 833, 1052))?.edges, [.right, .bottom], "a corner")
    t.equal(d(box(15, 15, 833, 1052))?.dy, 100, "with its own amount")
    t.equal(d(box(315, 215, 733, 952)) == nil, true, "a move is not a resize, however far it went")
    t.equal(d(box(15, 15, 734, 952)) == nil, true, "an app rounding a point off is not one either")
    t.equal(d(box(-35, 15, 784, 952))?.edges, [.left],
            "the left edge dragged while the right one drifts a point: still the left edge")
}

h.test("letting go of an edge moves the split to where the window now ends") { t in
    let wm = draggingFixture()
    let before = wm.render().frames
    t.equalBox(before[1], box(15, 15, 733, 952), "fixture: w1's frame, gaps applied")
    t.equalBox(before[2], box(764, 15, 733, 468), "fixture: w2's")

    // The user pulled w1's right edge 100 to the right and let go.
    let held = box(15, 15, 833, 952)
    guard let gesture = ResizeGesture.delta(from: before[1]!, to: held) else {
        t.expect(false, "the gesture reads as a resize"); return
    }
    t.equal(wm.resizeWindow(1, dx: gesture.dx, dy: gesture.dy, edges: gesture.edges), true, "it moved")

    let after = wm.render().frames
    t.equalBox(after[1], held, "w1's tile is the frame the user let go of")
    t.equalBox(after[2], box(864, 15, 633, 468), "w2's left edge followed by the same 100")
    t.equalBox(after[3], box(864, 499, 312, 468), "so did w3's")
    t.equal(after[4]?.maxX, before[4]?.maxX, "and nothing on the far side of the display moved")
}

h.test("resizeactive grows a floating window about its centre") { t in
    let wm = draggingFixture()
    wm.toggleFloating(4)
    wm.floatingFrames[4] = box(400, 300, 600, 400)
    t.equal(wm.resizeWindow(4, dx: 50, dy: 20), true, "a float takes the delta as size")
    t.equalBox(wm.render().floating[4], box(375, 290, 650, 420),
               "split between both edges — the centre is where it was")

    wm.floatingFrames[4] = box(400, 300, 600, 400)
    t.equal(wm.growWindow(4, dx: 30, dy: 0), true, "growactive on a float")
    t.equalBox(wm.render().floating[4], box(385, 300, 630, 400),
               "is the same thing — a float has no split to be relative to")

    wm.floatingFrames[4] = box(400, 300, 600, 400)
    wm.growWindow(4, dx: -5000, dy: -5000)
    t.equalBox(wm.render().floating[4], box(650, 450, 100, 100),
               "it cannot be shrunk out of reach, and the floor is centred like any other size")

    wm.floatingFrames[4] = box(400, 300, 601, 401)
    wm.growWindow(4, dx: 0, dy: 0)
    t.equalBox(wm.render().floating[4], box(400, 300, 601, 401), "nothing to share out, nothing moves")
}

h.test("a float growing about its centre is kept on the display, inside gaps_out") { t in
    let wm = draggingFixture()   // Gaps() — gaps_out is 15
    wm.toggleFloating(4)
    wm.floatingFrames[4] = box(0, 0, 600, 400)   // flush with the top-left corner
    wm.growWindow(4, dx: 100, dy: 100)
    t.equalBox(wm.render().floating[4], box(15, 15, 700, 500),
               "it grew, it did not slide off — and it landed on the gap, not the edge")

    wm.floatingFrames[4] = box(912, 582, 600, 400)   // flush with the bottom-right corner
    wm.growWindow(4, dx: 100, dy: 100)
    t.equalBox(wm.render().floating[4], box(797, 467, 700, 500), "and the same at the far corner")

    wm.floatingFrames[4] = box(100, 100, 1400, 800)
    wm.growWindow(4, dx: 400, dy: 0)
    t.equalBox(wm.render().floating[4], box(15, 100, 1482, 800),
               "asked to outgrow the display, it fills the display inside gaps_out instead")
    wm.growWindow(4, dx: 100, dy: 0)
    t.equalBox(wm.render().floating[4], box(15, 100, 1482, 800), "and stops there")
    wm.growWindow(4, dx: -100, dy: 0)
    t.equalBox(wm.render().floating[4], box(65, 100, 1382, 800), "shrinking back is still centred")

    wm.gaps = Gaps(inner: 8, outer: 40)
    wm.floatingFrames[4] = box(100, 100, 1400, 800)
    wm.growWindow(4, dx: 400, dy: 0)
    t.equalBox(wm.render().floating[4], box(40, 100, 1432, 800), "the margin is the configured gaps_out")
}

h.test("a float let go of past the margin snaps back inside it") { t in
    let wm = draggingFixture()   // Gaps() — gaps_out is 15
    wm.toggleFloating(4)
    wm.floatingFrames[4] = box(300, 200, 600, 400)
    t.equal(wm.settleFloat(4), false, "well inside: nothing to do, and nothing to write")
    t.equalBox(wm.render().floating[4], box(300, 200, 600, 400), "left exactly where it was")

    wm.floatingFrames[4] = box(-100, -50, 600, 400)   // dropped past the top-left corner
    t.equal(wm.settleFloat(4), true, "past the corner, it moves")
    t.equalBox(wm.render().floating[4], box(15, 15, 600, 400), "onto the gap, its size untouched")

    wm.floatingFrames[4] = box(1000, 700, 600, 400)   // and past the bottom-right one
    wm.settleFloat(4)
    t.equalBox(wm.render().floating[4], box(897, 567, 600, 400), "the same at the far corner")

    wm.floatingFrames[4] = box(5, 300, 600, 400)   // dropped inside the gap band
    wm.settleFloat(4)
    t.equalBox(wm.render().floating[4], box(15, 300, 600, 400), "the band is out of bounds too")

    wm.floatingFrames[4] = box(-100, 100, 1600, 400)   // wider than the display
    wm.settleFloat(4)
    t.equalBox(wm.render().floating[4], box(15, 100, 1482, 400), "too big to fit is cut to the margin")

    t.equal(wm.settleFloat(1), false, "a tile has no float to settle")
}

h.test("a float dropped on the other display comes back to its workspace's display") { t in
    let left = box(0, 0, 1512, 982)
    let right = box(1512, 0, 1920, 1080)
    let wm = WorkspaceManager()
    wm.setMonitors([Monitor(id: 1, frame: left, usable: left),
                    Monitor(id: 2, frame: right, usable: right)])
    wm.switchTo(workspace: wm.activeWorkspace[1]!)
    wm.addWindow(1); wm.addWindow(2)
    wm.toggleFloating(2)

    wm.floatingFrames[2] = box(3000, 800, 600, 400)   // dragged onto the right display
    wm.settleFloat(2)
    t.equalBox(wm.render().floating[2], box(897, 567, 600, 400),
               "back on its own display, at the nearest edge — where the render would have recentred it")
    t.equal(wm.workspaceIndex(of: 2), wm.activeWorkspace[1], "its workspace is unchanged")
}

// MARK: - Dock swipes

// The numbers `DockSwipeTap` reads off the event, by name.
let began = DockSwipe.Phase.began, changed = DockSwipe.Phase.changed
let ended = DockSwipe.Phase.ended, cancelled = DockSwipe.Phase.cancelled
let horizontal = DockSwipe.Motion.horizontal, vertical = DockSwipe.Motion.vertical

h.test("a sideways swipe steps once, however long it runs") { t in
    var swipe = DockSwipe()
    t.equal(swipe.feed(phase: began, swipeMask: 0, motion: DockSwipe.Motion.none), nil,
            "began, before the trackpad has settled on an axis")
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left, motion: horizontal), .left,
            "the first horizontal report is the step")
    for _ in 0..<40 {
        t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left, motion: horizontal), nil,
                "the rest of the run is silent — one flick is not ten workspaces")
    }
    t.equal(swipe.feed(phase: ended, swipeMask: DockSwipe.Mask.left, motion: horizontal), nil, "ended")
}

h.test("a swipe whose direction is known on began steps on began") { t in
    var swipe = DockSwipe()
    t.equal(swipe.feed(phase: began, swipeMask: DockSwipe.Mask.right, motion: horizontal), .right,
            "no need to wait for a changed")
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.right, motion: horizontal), nil, "and only once")
}

h.test("a vertical swipe is swallowed and never steps") { t in
    var swipe = DockSwipe()
    t.equal(swipe.feed(phase: began, swipeMask: 0, motion: DockSwipe.Motion.none), nil, "began")
    for mask in [DockSwipe.Mask.up, DockSwipe.Mask.down] {
        for _ in 0..<5 {
            t.equal(swipe.feed(phase: changed, swipeMask: mask, motion: vertical), nil, "vertical, mask \(mask)")
        }
    }
    t.equal(swipe.feed(phase: ended, swipeMask: DockSwipe.Mask.up, motion: vertical), nil, "ended")
}

h.test("the axis and the direction have to agree before a swipe steps") { t in
    var swipe = DockSwipe()
    _ = swipe.feed(phase: began, swipeMask: 0, motion: DockSwipe.Motion.none)
    t.equal(swipe.feed(phase: changed, swipeMask: 0, motion: horizontal), nil,
            "horizontal, but no direction yet — not yet, rather than no")
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left, motion: DockSwipe.Motion.none), nil,
            "a direction with no motion behind it")
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left | DockSwipe.Mask.right, motion: horizontal), nil,
            "both bits is not a direction")
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.up, motion: horizontal), nil,
            "an up mask on a horizontal motion is nothing this code knows")
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.right, motion: horizontal), .right,
            "still armed through all of that, so the first real answer steps")
}

h.test("ended and cancelled both release the latch for the next gesture") { t in
    var swipe = DockSwipe()
    for release in [ended, cancelled] {
        _ = swipe.feed(phase: began, swipeMask: 0, motion: DockSwipe.Motion.none)
        t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left, motion: horizontal), .left, "steps")
        _ = swipe.feed(phase: release, swipeMask: DockSwipe.Mask.left, motion: horizontal)
        t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left, motion: horizontal), nil,
                "a changed after \(release) belongs to no gesture")
    }
    _ = swipe.feed(phase: began, swipeMask: 0, motion: DockSwipe.Motion.none)
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.right, motion: horizontal), .right,
            "the next began arms afresh")
}

h.test("a gesture the tap joined half-way through does not step") { t in
    var swipe = DockSwipe()
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left, motion: horizontal), nil,
            "no began was seen — the tap was started mid-swipe")
    _ = swipe.feed(phase: ended, swipeMask: DockSwipe.Mask.left, motion: horizontal)
    _ = swipe.feed(phase: began, swipeMask: 0, motion: DockSwipe.Motion.none)
    t.equal(swipe.feed(phase: changed, swipeMask: DockSwipe.Mask.left, motion: horizontal), .left,
            "the next whole gesture does")
}

h.test("a phase this code does not know neither arms nor releases") { t in
    var swipe = DockSwipe()
    _ = swipe.feed(phase: began, swipeMask: 0, motion: DockSwipe.Motion.none)
    t.equal(swipe.feed(phase: 16, swipeMask: DockSwipe.Mask.left, motion: horizontal), .left,
            "an unknown phase is treated as changed: still armed, so a horizontal report steps")
    _ = swipe.feed(phase: 16, swipeMask: DockSwipe.Mask.left, motion: horizontal)
    var fresh = DockSwipe()
    t.equal(fresh.feed(phase: 16, swipeMask: DockSwipe.Mask.left, motion: horizontal), nil,
            "but it does not arm — a renumbered phase field degrades to swallow-only")
}

h.test("the swipe follows Natural scrolling the way the Spaces swipe does") { t in
    t.equal(WorkspaceTarget.swipe(.left, naturalScrolling: true), .next,
            "content tracks the fingers: dragging the desktop left pulls the next workspace in from the right")
    t.equal(WorkspaceTarget.swipe(.right, naturalScrolling: true), .previous, "and the other way")
    t.equal(WorkspaceTarget.swipe(.left, naturalScrolling: false), .previous,
            "with the setting off macOS reverses its Spaces swipe, and so does toe")
    t.equal(WorkspaceTarget.swipe(.right, naturalScrolling: false), .next, "and the other way")
}

// MARK: - The fullscreen freeze

h.test("a fullscreen window suspends the verbs that act on the Space underneath") { t in
    // The list the coordinator refuses while a native-fullscreen window holds the focus. Its
    // whole content is "would this happen on the Space underneath, where nobody can see it".
    // `killactive` is in it because the window it would close is the tile that held the focus
    // before fullscreen, not the fullscreen window the user is looking at.
    for command: Command in [.moveFocus(.left), .swapWindow(.up), .moveWindow(.down),
                             .workspace(.next), .workspace(.index(3)), .workspace(.former),
                             .moveToWorkspace(2, follow: true),
                             .moveToWorkspace(2, follow: false), .killActive] {
        t.equal(command.suspendedByFullscreen, true,
                "\(CommandLabel.describe(command)) moves, or closes, a window nobody can see")
    }

    // Everything else goes through: a size, a theme, a menu, a shell line — nothing that leaves
    // the user with a screen they did not arrange.
    for command: Command in [.toggleFloating, .toggleSplit, .swapSplit,
                             .growActive(dx: 100, dy: 0), .resizeActive(dx: 100, dy: 0),
                             .exec("ghostty"), .reload, .menu(.root), .quit,
                             .theme("tokyo-night"), .removeTheme("tokyo-night"),
                             .background("1.png"), .nextBackground] {
        t.equal(command.suspendedByFullscreen, false,
                "\(CommandLabel.describe(command)) is nothing a fullscreen window hides")
    }
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
    t.equal(c.gaps, Gaps(inner: 8, outer: 15), "the shipped gaps")
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
    t.equal(binding("super-equal")?.command, .growActive(dx: 100, dy: 0), "SUPER+= makes the window wider")
    t.equal(binding("super-equal")?.keyCode, 0x18, "= key code")
    t.equal(binding("super-minus")?.command, .growActive(dx: -100, dy: 0), "SUPER+- narrower")
    t.equal(binding("super-shift-minus")?.command, .growActive(dx: 0, dy: -100), "SHIFT for the vertical axis")
    t.equal(binding("super-shift-minus")?.modifiers, [.option, .shift], "SUPER+SHIFT")
    t.equal(binding("super-shift-equal")?.command, .growActive(dx: 0, dy: 100), "Omarchy's four keys")
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
    t.equal(binding("super-ctrl-space")?.command, .menu(.background),
            "SUPER+CTRL+SPACE opens the background picker, as it does in Omarchy")
    t.equal(binding("super-shift-ctrl-space")?.command, .menu(.theme),
            "and SUPER+SHIFT+CTRL+SPACE the theme one, the same key upstream binds")
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

h.test("the slide on a swipe is configurable and off by default") { t in
    let c = Config.makeDefault()
    t.equal(c.animations.slideOnSwipe, false, "off until asked for: it needs Screen Recording")
    t.equal(c.animations.slideDuration, 0.3, "about what Spaces takes")

    let on = try Config.parse("[animations]\nslide_on_swipe = true\nslide_duration = 0.5\n")
    t.equal(on.animations.slideOnSwipe, true, "on")
    t.equal(on.animations.slideDuration, 0.5, "duration")
    t.equal(on.warnings, [], "no warnings")

    let bad = try Config.parse("[animations]\nslide_on_swipe = \"yes\"\nslide_duration = nan\n")
    t.equal(bad.animations.slideOnSwipe, false, "a non-boolean keeps the default")
    t.equal(bad.animations.slideDuration, 0.3, "a NaN never reaches Core Animation")
    t.equal(bad.warnings.contains { $0.contains("animations.slide_on_swipe") }, true, "the boolean is named")
    t.equal(bad.warnings.contains { $0.contains("animations.slide_duration") }, true, "and the duration")

    let slow = try Config.parse("[animations]\nslide_duration = 10\n")
    t.equal(slow.animations.slideDuration, 0.3, "out of range keeps the default")
}

h.test("the slide follows the target, not the fingers") { t in
    t.equal(WorkspaceSlide.direction(for: .next), .left, "the next workspace comes in from the right")
    t.equal(WorkspaceSlide.direction(for: .previous), .right, "the previous one from the left")
    t.equal(WorkspaceSlide.direction(for: .index(3)), nil, "a numbered switch does not slide")
    t.equal(WorkspaceSlide.direction(for: .former), nil, "nor the last-visited one")
    // Natural scrolling is folded into the target before the slide sees it, so either setting
    // slides the way Spaces would under it.
    for natural in [true, false] {
        let target = WorkspaceTarget.swipe(.left, naturalScrolling: natural)
        t.equal(WorkspaceSlide.direction(for: target), natural ? .left : .right,
                "fingers left, natural scrolling \(natural ? "on" : "off")")
    }
}

h.test("a slide's mask is the windows on the picture, clipped to it") { t in
    let area = box(0, 40, 1440, 860)                       // below a menu bar
    let cut = WorkspaceSlide.cutouts([(box(10, 50, 700, 400), 12),
                                      (box(1400, 800, 200, 200), 8),   // half off the right and bottom
                                      (box(1500, 40, 100, 100), 8),    // on another display
                                      (box(0, 0, 1440, 40), 0)],       // the menu bar's strip
                                     in: area)
    t.equal(cut.count, 2, "what is on the picture, and only that")
    t.equalBox(cut[0].box, box(10, 10, 700, 400), "relative to the picture's top-left")
    t.equal(cut[0].radius, 12, "at the window's own radius")
    t.equalBox(cut[1].box, box(1400, 760, 40, 100), "clipped to the edge it runs off")
}

h.test("the two pictures of a slide stay one width apart") { t in
    t.equal(WorkspaceSlide.travel(.left, width: 1440),
            WorkspaceSlide.Travel(outgoingEnd: -1440, incomingStart: 1440), "leaving to the left")
    t.equal(WorkspaceSlide.travel(.right, width: 1440),
            WorkspaceSlide.Travel(outgoingEnd: 1440, incomingStart: -1440), "leaving to the right")
}

h.test("the macOS behaviours toe takes over are configurable") { t in
    let off = try Config.parse("[misc]\ndisable_expose_shortcuts = false\nprevent_hiding = false\ndisable_wallpaper_click = false\ndisable_edge_tiling = false\nautohide_dock = false\n")
    t.equal(off.misc.disableExposeShortcuts, false, "the Exposé shortcuts can be handed back")
    t.equal(off.misc.preventHiding, false, "hiding can be allowed")
    t.equal(off.misc.disableWallpaperClick, false, "the wallpaper click can be handed back")
    t.equal(off.misc.disableEdgeTiling, false, "and macOS can go on tiling a drag to the edge")
    t.equal(off.misc.autohideDock, false, "the Dock can be left showing")
    t.equal(off.warnings, [], "no warnings")

    let absent = try Config.parse("[general]\ngaps_in = 5\n")
    t.equal(absent.misc.disableExposeShortcuts, true, "omitting the table keeps the defaults")
    t.equal(absent.misc.preventHiding, true, "omitting the table keeps the defaults")
    t.equal(absent.misc.disableWallpaperClick, true, "omitting the table keeps the defaults")
    t.equal(absent.misc.disableEdgeTiling, true, "omitting the table keeps the defaults")
    t.equal(absent.misc.autohideDock, true, "omitting the table keeps the defaults")

    let bad = try Config.parse("[misc]\nprevent_hiding = 1\ndisable_wallpaper_click = \"no\"\ndisable_edge_tiling = \"nope\"\nautohide_dock = \"sometimes\"\n")
    t.equal(bad.misc.preventHiding, true, "a non-boolean keeps the default")
    t.equal(bad.misc.disableWallpaperClick, true, "a non-boolean keeps the default")
    t.equal(bad.misc.disableEdgeTiling, true, "a non-boolean keeps the default")
    t.equal(bad.misc.autohideDock, true, "a non-boolean keeps the default")
    t.equal(bad.warnings.contains { $0.contains("misc.prevent_hiding") }, true,
            "and says so in the menu bar")
    t.equal(bad.warnings.contains { $0.contains("misc.disable_wallpaper_click") }, true,
            "and says so for the wallpaper click too")
    t.equal(bad.warnings.contains { $0.contains("misc.disable_edge_tiling") }, true,
            "and for the edge tiling")
    t.equal(bad.warnings.contains { $0.contains("misc.autohide_dock") }, true,
            "and for the Dock")
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

    // The shipped config binds them itself, so nothing should be duplicated.
    let shipped = try Config.parse(Config.defaultTOML)
    for command in [Command.quit, .reload, .menu(.background), .menu(.theme),
                    .growActive(dx: 100, dy: 0), .growActive(dx: 0, dy: 100)] {
        t.equal(shipped.bindings.filter { $0.command == command }.count, 1,
                "the shipped config binds \(command) exactly once")
    }

    // The one entry on the list that is not an escape hatch. It is there for the same reason the
    // others are — a config is never rewritten, so a key added later reaches nobody who already
    // had one — and it obeys the same two rules, which is what makes it something you can take
    // back rather than something done to you.
    t.equal(binding(old, .menu(.background))?.source, "super-ctrl-space",
            "a config written before backgrounds existed still gets Omarchy's key for them")
    t.equal(binding(old, .menu(.theme))?.source, "super-shift-ctrl-space", "and the theme one")
    let moved = try Config.parse("[binds]\n\"super-b\" = \"menu background\"\n")
    t.equal(binding(moved, .menu(.background))?.source, "super-b",
            "binding it elsewhere takes the key back")
    // The key changed hands in the release that followed Omarchy onto quattro. A config that
    // still names the old command keeps it, because a fallback never lands on a taken key.
    let stepping = try Config.parse("[binds]\n\"super-ctrl-space\" = \"nextbackground\"\n")
    t.equal(binding(stepping, .nextBackground)?.source, "super-ctrl-space",
            "an upgrader who had the old line goes on stepping through pictures")
    t.equal(binding(stepping, .menu(.background)), nil, "and is not given the picker on top of it")
    t.equal(moved.bindings.filter { $0.command == .menu(.background) }.count, 1, "and not twice")
    let taken = try Config.parse("[binds]\n\"super-ctrl-space\" = \"killactive\"\n")
    t.equal(binding(taken, .menu(.background)), nil, "and a key you already use is left alone")

    // The resize keys are on the list on the same terms. All four of them, because a config that
    // predates them has none, and one without the other would be half a feature.
    t.equal(binding(old, .growActive(dx: 100, dy: 0))?.source, "super-equal",
            "a config written before resizing existed still gets Omarchy's key for it")
    t.equal(binding(old, .growActive(dx: -100, dy: 0))?.source, "super-minus", "and its pair")
    t.equal(binding(old, .growActive(dx: 0, dy: -100))?.source, "super-shift-minus", "and the vertical pair")
    t.equal(binding(old, .growActive(dx: 0, dy: 100))?.source, "super-shift-equal", "all four")
    // Any resizing verb at all is an answer, whatever its amount or its sign convention: a
    // config that has Hyprland's resizeactive by 50 on its own keys has decided how it resizes
    // and is not handed growactive 100 on four more.
    let fifty = try Config.parse("[binds]\n\"super-l\" = \"resizeactive 50 0\"\n")
    t.equal(fifty.bindings.filter { $0.command.resizes }.count, 1, "your own resize binding stands alone")
    t.equal(binding(fifty, .resizeActive(dx: 50, dy: 0))?.source, "super-l", "on your key")
    // And a resize key already used for something else stays that way; the other three land.
    let equal = try Config.parse("[binds]\n\"super-equal\" = \"killactive\"\n")
    t.equal(binding(equal, .killActive)?.source, "super-equal", "SUPER+= stays yours")
    t.equal(binding(equal, .growActive(dx: 100, dy: 0)), nil, "and is not given the resize on top")
    t.equal(binding(equal, .growActive(dx: -100, dy: 0))?.source, "super-minus", "while SUPER+- still lands")
    t.equal(binding(taken, .killActive)?.source, "super-ctrl-space", "still doing what you asked")
}

h.test("nan and infinity are refused rather than reaching the layout") { t in
    // TOML spells both, and Double("nan") accepts them. A NaN gap defeats every == in the
    // coordinator: the window is re-written on every render forever, the correction budget
    // never resets, and the NaN is passed to other applications over Accessibility.
    for spelling in ["nan", "inf", "-inf", "+inf"] {
        let c = try Config.parse("[general]\ngaps_in = \(spelling)\n")
        t.equal(c.gaps.inner, 8, "gaps_in = \(spelling) keeps the default")
        t.equal(c.gaps.inner.isFinite, true, "gaps_in = \(spelling) leaves a finite gap")
        t.equal(c.warnings.contains { $0.contains("general.gaps_in") }, true,
                "gaps_in = \(spelling) warns")
    }

    let out = try Config.parse("[general]\ngaps_out = nan\n")
    t.equal(out.gaps.outer, 15, "gaps_out = nan keeps the default")
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
    t.equal(hex.gaps.inner, 8, "a 1024 point gap keeps the default")
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

h.test("force_split and split_bias take only their three values") { t in
    // Both fell through `intValue` unchecked, so `force_split = 7` behaved exactly like 2 and a
    // typo was indistinguishable from the default.
    let c = try Config.parse("[dwindle]\nforce_split = 7\nsplit_bias = 9\n")
    t.equal(c.dwindle.forceSplit, 2, "force_split = 7 keeps the default")
    t.equal(c.dwindle.splitBias, 0, "split_bias = 9 keeps the default")
    t.equal(c.warnings, ["dwindle.force_split: must be 0, 1 or 2, using 2",
                         "dwindle.split_bias: must be 0, 1 or 2, using 0"],
            "each names the values it could have been and the one it is keeping")

    let negative = try Config.parse("[dwindle]\nforce_split = -1\n")
    t.equal(negative.dwindle.forceSplit, 2, "a negative force_split keeps the default")
    t.equal(negative.warnings.count, 1, "and says so")

    let fine = try Config.parse("[dwindle]\nforce_split = 1\nsplit_bias = 2.0\n")
    t.equal(fine.dwindle.forceSplit, 1, "1 is read")
    t.equal(fine.dwindle.splitBias, 2, "a whole float still reads as the integer it is")
    t.equal(fine.warnings, [], "and neither warns")

    let bar = try Config.parse("[bar]\npersistent_workspaces = 11\n")
    t.equal(bar.warnings, ["bar.persistent_workspaces: must be a whole number from 0 to 10, using \(bar.bar.persistentWorkspaces)"],
            "a longer list is spelled as a range")
}

h.test("a number in quotes warns rather than being read as absent") { t in
    // `gaps_in = "5"` used to fall through `raw?.doubleValue` as nil — the same nil as a key
    // that was never written — so it was dropped without a word, while `gaps_in = 999` got a
    // warning. From the outside both read as "toe ignored my config".
    let c = try Config.parse("""
        [general]
        gaps_in = "5"
        [border]
        width = "2"
        [menu]
        font_size = "18"
        [dwindle]
        force_split = "1"
        [bar]
        persistent_workspaces = "3"
        [floating]
        width = "0.5"
        max_aspect_ratio = true
        """)
    t.equal(c.gaps.inner, 8, "gaps_in in quotes keeps the default")
    t.equal(c.border.width, 2, "border.width in quotes keeps the default")
    t.equal(c.menu.fontSize, 18, "menu.font_size in quotes keeps the default")
    t.equal(c.dwindle.forceSplit, 2, "force_split in quotes keeps the default")
    t.equal(c.bar.persistentWorkspaces, WorkspaceStrip.defaultPersistent, "persistent_workspaces in quotes keeps the default")
    t.equal(c.floating.width, 0.70, "floating.width in quotes keeps the default")
    t.equal(c.floating.maxAspectRatio, Config().floating.maxAspectRatio, "a boolean where a ratio goes keeps the default")
    t.equal(c.warnings.count, 7, "one warning each")
    t.expect(c.warnings.contains("general.gaps_in: must be a number, using 8"), "the number is named, and so is what is kept")
    t.expect(c.warnings.contains("border.width: must be a number, using 2"), "border.width too")
    t.expect(c.warnings.contains("menu.font_size: must be a number, using 18"), "menu.font_size too")
    t.expect(c.warnings.contains("dwindle.force_split: must be 0, 1 or 2, using 2"), "a choice names its values")
    t.expect(c.warnings.contains { $0.hasPrefix("bar.persistent_workspaces: must be") }, "persistent_workspaces too")
    t.expect(c.warnings.contains("floating.width: must be a number, using 0.7"), "floating.width too")
    t.expect(c.warnings.contains { $0.hasPrefix("floating.max_aspect_ratio: must be a number") }, "and the boolean")

    // The regression guard that matters: a key that is simply not there is still silent.
    let absent = try Config.parse("[general]\n[border]\n[menu]\n[dwindle]\n[bar]\n[floating]\n")
    t.equal(absent.warnings, [], "an absent key is the default, and nothing to warn about")
    t.equal(absent.gaps.inner, 8, "with the default in place")
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
    t.equalBox(restored.render().frames[1], box(15, 15, 1697, 1370), "w1 fills half the new display")
    t.equalBox(restored.render().frames[2], box(1728, 15, 1697, 1370), "w2 the other half")
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
    t.equal(beyond.map(\.index), [1, 2, 3, 4, 8],
            "a workspace past the persistent five appears once it has windows, and the "
            + "padding gives up a slot for it rather than adding a sixth")

    // The bug: persistent is a floor on how many slots there are, not a claim on 1-5. Six
    // workspaces in use is already past the floor, so the empty 4 between them stays off.
    let full = WorkspaceStrip.items(for: states(occupied: [1, 2, 3, 5, 6, 9], focused: 1))
    t.equal(full.map(\.index), [1, 2, 3, 5, 6, 9], "no empty 4 once five slots are earned")
    t.equal(full.map(\.dim), [false, false, false, false, false, false], "and none is dimmed")

    // Exactly at the floor: five in use, nothing padded, and again no empty 4.
    let atFloor = WorkspaceStrip.items(for: states(occupied: [1, 2, 3, 5, 6], focused: 1))
    t.equal(atFloor.map(\.index), [1, 2, 3, 5, 6], "five in use is already five slots")

    // One short of it: the lowest empty workspace is padded in to make the fifth slot.
    let oneShort = WorkspaceStrip.items(for: states(occupied: [2, 3, 5, 6], focused: 2))
    t.equal(oneShort.map(\.index), [1, 2, 3, 5, 6], "four in use, so the lowest empty joins")
    t.equal(oneShort.map(\.dim), [true, false, false, false, false], "the padded one is dimmed")

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
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
    m.move(by: 2)
    t.equal(m.selection, 2, "moved down two")
    m.type("q")
    t.equal(m.selection, 0, "a keystroke re-ranks the list, so the old index means nothing")
    t.equal(m.visible.map(\.title), ["Quit"], "and the list is what was typed")
}

h.test("a submenu is entered, backed out of, and clears the query on the way in") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .on, config: Config()), visibleRows: 10)
    t.equal(m.prompt, "Go…", "walker's placeholder at the root")
    m.type("setup")
    t.equal(m.visible.count, 1, "one row matches 'setup'")
    t.equal(m.activate(), .pushed, "Setup descends rather than dispatching")
    t.equal(m.query, "", "the query does not follow you into the submenu")
    t.equal(m.breadcrumb, ["Setup"], "the level is named")
    t.equal(m.prompt, "Setup…", "and the placeholder says where you are")
    t.equal(m.visible.map(\.title),
            ["Run on startup", "Workspace slide", "Focus border", "Auto-hide Dock"],
            "what toe can actually change for you")
    t.equal(m.pop(), .popped, "Escape climbs one level")
    t.equal(m.pop(), .closed, "and closes at the root")
}

h.test("backspace eats the query, then leaves the submenu") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
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
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
    m.type("startup")
    t.equal(m.visible.map(\.title), ["Run on startup"],
            "found two levels down without anyone having to go there")
    t.equal(m.visible.first?.subtitle, "Setup", "and the row says where it lives")
    t.equal(m.activate(), .toggleLoginItem, "acting on it needs no descent either")

    var deep = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
    deep.type("keyb")
    t.equal(deep.visible.map(\.title), ["Keybindings"], "the same for the other branch")
    t.equal(deep.visible.first?.subtitle, "Learn", "named by its path")
    t.equal(deep.activate(), .page(.keybindings), "and it still opens the page")
}

h.test("a branch found by searching is still a branch") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
    m.type("learn")
    t.equal(m.visible.map(\.title), ["Learn"], "the branch itself matches, not only its children")
    t.equal(m.visible.first?.subtitle, nil, "a row at the level you are on has no path to show")
    t.equal(m.activate(), .pushed, "and it descends the way it does unfiltered")
}

h.test("a searched list carries no icons") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 20)
    t.expect(m.visible.contains { $0.icon != nil }, "a level draws its glyphs")
    m.type("e")
    t.expect(m.visible.count > 1, "the search turns up rows from several levels")
    t.expect(m.visible.allSatisfy { $0.icon == nil },
             "and none of them indents past a glyph the row beneath it has not got")
    m.backspace()
    t.expect(m.visible.contains { $0.icon != nil }, "the level gets its glyphs back")
}

h.test("an empty query is one level at a time, with no paths") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
    m.type("z")
    t.equal(m.visible.count, 0, "nothing matches")
    m.backspace()
    t.equal(m.visible.map(\.title), ["Learn", "Style", "Setup", "Quit"], "the level comes back")
    t.expect(m.visible.allSatisfy { $0.subtitle == nil },
             "and the paths go away with the search that needed them")
}

h.test("the rows lead where the menu says they do") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
    t.equal(m.visible.map(\.title), ["Learn", "Style", "Setup", "Quit"], "the whole menu, bare minimum")
    t.equal(m.visible.map(\.leadsOn), [true, true, true, false], "three lead on, Quit acts")
    m.type("quit")
    t.equal(m.activate(), .run(.quit), "and Quit dispatches rather than descending")

    var learn = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
    learn.type("learn")
    _ = learn.activate()
    t.equal(learn.activate(), .page(.keybindings), "Learn holds the keybindings page")
}

h.test("the startup row reads the state it is handed") { t in
    func startup(_ state: LoginItemState) -> MenuItem? {
        let root = MenuModel.root(loginItem: state, config: Config())
        // By title rather than by position: Setup moves as Install and Remove come and go with
        // the catalogue. The row is looked up by title too — Setup holds the slide switch as
        // well, and in the case below the startup row is the one of the two that is missing.
        guard case .submenu(let setup)? = root.first(where: { $0.title == "Setup" })?.action
        else { return nil }
        return setup.first { $0.title == "Run on startup" }
    }
    t.equal(startup(.on)?.value, "on", "the row shows launchd's answer, not a preference")
    t.equal(startup(.on)?.action, .toggleLoginItem, "and pressing it flips it")
    t.equal(startup(.off)?.value, "off", "the other way round")
    t.equal(startup(.unavailable("needs /Applications"))?.title, nil,
            "where it cannot work the row is not there at all — a switch you can see but not "
            + "throw is worse than one you were never offered")
}

h.test("the switches live under Setup, and each row is the line it writes") { t in
    func setup(_ config: Config) -> [MenuItem] {
        let root = MenuModel.root(loginItem: .off, config: config)
        guard case .submenu(let rows)? = root.first(where: { $0.title == "Setup" })?.action
        else { return [] }
        return rows
    }
    let shipped = try Config.parse(Config.defaultTOML)
    t.equal(setup(shipped).map(\.title).suffix(3),
            ["Workspace slide", "Focus border", "Auto-hide Dock"],
            "toe's own switches, under the config and the startup row")

    // Each switch is checked through the writer the menu throws it with, against the parser the
    // config is read with: a `table` or a `key` that named nothing would leave a row that looks
    // like it works and a file that never changes, which is the one failure the runtime guard
    // (`Coordinator.rewriteConfig`'s verify) can only turn into a log line after the fact.
    for setting in ConfigSwitch.allCases {
        let was = setting.value(in: shipped)
        let edited = ConfigWriter.setting(setting.key, to: was ? "false" : "true",
                                          inTable: setting.table, of: Config.defaultTOML)
        t.equal(setting.value(in: try Config.parse(edited)), !was,
                "\(setting.rawValue): the table and the key are the ones the parser reads")

        let row = setup(try Config.parse(edited)).first { $0.title == setting.title }
        t.equal(row?.value, was ? "off" : "on", "\(setting.rawValue): the row shows the config")
        t.equal(row?.icon, was ? .toggleOff : .toggleOn, "\(setting.rawValue): and draws it")
        t.equal(row?.action, .toggleSetting(setting),
                "\(setting.rawValue): and pressing it flips that switch, not another")
    }

    // What `QuickMenu` redraws the level with while the file is being read back.
    var shown = shipped
    ConfigSwitch.dock.set(false, in: &shown)
    t.equal(setup(shown).first { $0.title == "Auto-hide Dock" }?.value, "off",
            "a switch set in memory shows in the row, for the moment before the reload lands")
    t.equal(setup(shown).first { $0.title == "Focus border" }?.value, "on", "and moves nothing else")

    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10,
                      path: MenuRoute.setup.path)
    t.equal(m.breadcrumb, ["Setup"], "`menu setup` opens on the level")
    m.type("slide")
    t.equal(m.activate(), .toggleSetting(.slide),
            "and Return asks the app layer to throw the switch under the cursor")
    // The level the switches used to live on is gone, and the two routes that opened it now open
    // the one they moved to, so a config written when the slide was three levels down still works.
    t.equal(try CommandParser.parse("menu toggle"), .menu(.setup), "Omarchy's alias follows the rows")
    t.equal(try CommandParser.parse("menu trigger"), .menu(.setup), "and so does its parent")
}

h.test("the Config row is your binding, not toe's idea of an editor") { t in
    func rows(_ toml: String, loginItem: LoginItemState = .off) throws -> [MenuItem] {
        MenuModel.setup(loginItem: loginItem, config: try Config.parse(toml))
    }

    // The shipped config: the row runs exactly the line the file bound, character for character.
    // Omarchy's `setup.config` first, then toe's own row — the ported rows lead.
    let shipped = try rows(Config.defaultTOML)
    t.equal(shipped.map(\.title),
            ["Config", "Run on startup", "Workspace slide", "Focus border", "Auto-hide Dock"],
            "every row, Omarchy's leading")
    t.equal(shipped.first?.action,
            .run(.exec("open -a \"Visual Studio Code\" ~/.config/toe/toe.toml")),
            "and it opens the config the way your config says to")

    // Point it at another editor and the row follows — nothing here names one.
    let zed = try rows("[binds]\n\"super-comma\" = \"exec open -a Zed ~/.config/toe/toe.toml\"\n")
    t.equal(zed.first?.action, .run(.exec("open -a Zed ~/.config/toe/toe.toml")),
            "the menu opens Zed because the config does")

    // On another key, too: the row is found by what it does, not by where it is bound.
    let moved = try rows("[binds]\n\"super-shift-c\" = \"exec open -e ~/.config/toe/toe.toml\"\n")
    t.equal(moved.first?.action, .run(.exec("open -e ~/.config/toe/toe.toml")),
            "SUPER+SHIFT+C is as good as SUPER+, — the row follows the binding")

    // An exec that opens something else is not an editor for this file.
    let unrelated = try rows("[binds]\n\"super-enter\" = \"exec open -a Ghostty\"\n")
    t.equal(unrelated.map(\.title),
            ["Run on startup", "Workspace slide", "Focus border", "Auto-hide Dock"],
            "no binding that opens the config, no row offering to")
    t.equal(MenuModel.root(loginItem: .unavailable("needs /Applications"),
                           config: try Config.parse("[binds]\n\"super-enter\" = \"exec open -a Ghostty\"\n"))
                .map(\.title),
            ["Learn", "Style", "Setup", "Quit"],
            "and with the startup row gone as well, Setup is down to the switch that always works")

    // The row is there even when the startup toggle cannot be.
    let buildDir = try rows(Config.defaultTOML, loginItem: .unavailable("needs /Applications"))
    t.equal(buildDir.map(\.title),
            ["Config", "Workspace slide", "Focus border", "Auto-hide Dock"],
            "the rows that work are still offered")
}

h.test("Setup holds the rows that work, and the startup one is not always among them") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .unavailable("needs /Applications"), config: Config()),
                      visibleRows: 10)
    t.equal(m.visible.map(\.title), ["Learn", "Style", "Setup", "Quit"],
            "Setup stays, on the strength of the one row that cannot be unavailable")
    m.type("startup")
    t.equal(m.visible.count, 0, "and the search cannot turn up the row that is not there")

    var slide = MenuState(root: MenuModel.root(loginItem: .unavailable("needs /Applications"),
                                               config: Config()), visibleRows: 10)
    slide.type("slide")
    t.equal(slide.visible.map(\.subtitle), ["Setup"], "while the switch is found under Setup")
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

// MARK: - A download, in the menu

/// A Theme level mid-download: two themes on disk, two to be had, and Solitude being fetched.
///
/// Solitude's five pictures are deliberately lopsided — 100 KB, 100 KB, 100 KB, 100 KB and 4 MB —
/// because that is the shape upstream actually has and the shape the first version of the bar got
/// wrong. Uniform steps put four fifths of the bar behind a tenth of the bytes.
let solitudePictures = [100_000, 100_000, 100_000, 100_000, 4_000_000]

func downloadingStyle(fetching: Int, bytesDone: Int) -> StyleMenu {
    let pictures = solitudePictures.enumerated().map {
        RemoteFile(name: "\($0.offset)-x.webp", bytes: $0.element)
    }
    return StyleMenu(themes: [ThemeRef(slug: "gruvbox", name: "Gruvbox"),
                              ThemeRef(slug: "nord", name: "Nord")],
                     available: [RemoteTheme(slug: "solitude", name: "Solitude",
                                             backgrounds: pictures),
                                 RemoteTheme(slug: "lupine", name: "Lupine",
                                             backgrounds: [RemoteFile(name: "0-y.webp",
                                                                      bytes: 400_000)])],
                     current: "gruvbox",
                     downloading: ThemeDownload(slug: "solitude", fetching: fetching, total: 5,
                                                bytesDone: bytesDone,
                                                bytesTotal: solitudePictures.reduce(0, +)))
}

h.test("the bar measures bytes, so it does not race through the small pictures") { t in
    let total = solitudePictures.reduce(0, +)          // 4.4 MB, of which the last is 4 MB
    func at(_ bytesDone: Int) -> Double {
        ThemeDownload(slug: "solitude", fetching: 1, total: 5,
                      bytesDone: bytesDone, bytesTotal: total).fraction
    }
    // Four small pictures down and only the big one left. Counting files this was four fifths
    // done; in bytes it is under a tenth, which is the truth — and the difference is exactly the
    // stall the first version showed at the end.
    t.expect(at(400_000) < 0.1, "four of five pictures is under a tenth of the bytes")
    t.equal(at(total / 2), 0.5, "halfway through the bytes is halfway along the bar")
    t.equal(at(total), 1, "and all of them fills it")

    // The last picture arriving is most of the bar, and it arrives continuously — which is the
    // point of reporting bytes while a transfer is running rather than only when it ends.
    t.expect(at(400_000 + 2_000_000) > 0.5, "halfway into the last picture is past halfway")
}

h.test("a download's bar reaches its end") { t in
    let total = solitudePictures.reduce(0, +)
    // The complaint this fixes: every report but the last is sent before or during a transfer,
    // so without a last word the final state the row ever drew was however much of the last
    // picture had arrived when it was last asked.
    let last = ThemeDownload(slug: "solitude", fetching: 5, total: 5,
                             bytesDone: total, bytesTotal: total)
    t.equal(last.fraction, 1, "the last word fills the row")
    t.equal(last.label, "5/5", "with the count to match")

    // Both numbers come off the network and can disagree.
    t.equal(ThemeDownload(slug: "a", fetching: 1, total: 1,
                          bytesDone: 9_000_000, bytesTotal: 1_000_000).fraction, 1,
            "a transfer heavier than advertised fills the row rather than overrunning it")
    t.equal(ThemeDownload(slug: "a", fetching: 1, total: 1,
                          bytesDone: -5, bytesTotal: 1_000).fraction, 0, "and clamped below")
    t.equal(ThemeDownload(slug: "a", fetching: 0, total: 0,
                          bytesDone: 0, bytesTotal: 0).fraction, 0,
            "a theme with no pictures has no fraction to draw and is over at once")
}

h.test("a download's label names the picture in flight, not the last one finished") { t in
    t.equal(ThemeDownload(slug: "a", fetching: 0, total: 5,
                          bytesDone: 0, bytesTotal: 100).label, nil,
            "the palette step has nothing to count yet, so the row keeps showing its size")
    t.equal(ThemeDownload(slug: "a", fetching: 3, total: 5,
                          bytesDone: 40, bytesTotal: 100).label, "3/5",
            "then it names what is being fetched")
    // The label and the bar deliberately disagree until the end: one says what is happening, the
    // other how much of it is done.
    let mid = ThemeDownload(slug: "a", fetching: 5, total: 5, bytesDone: 10, bytesTotal: 100)
    t.equal(mid.label, "5/5", "the last picture is in flight")
    t.expect(mid.fraction < 0.2, "while the bar is still near the start of it")
}

h.test("the theme being downloaded is the row that fills") { t in
    let style = downloadingStyle(fetching: 3, bytesDone: 200_000)
    // Install lists what Omarchy publishes; Style lists what is on the disk. A download happens
    // in the first and lands in the second, which is why the fill is asserted on Install's rows
    // and the `✓` on Style's.
    let rows = MenuModel.installableThemes(style)
    guard let solitude = rows.first(where: { $0.title == "Solitude" }),
          let lupine = rows.first(where: { $0.title == "Lupine" }),
          let gruvbox = MenuModel.themes(style).first(where: { $0.title == "Gruvbox" }) else {
        return t.expect(false, "all three themes should have rows")
    }
    t.equal(solitude.progress, 200_000.0 / 4_400_000,
            "the one being fetched carries the fraction, in bytes")
    // The size was there to say what you were about to spend; once you have spent it the
    // question has become how much longer.
    t.equal(solitude.value, "3/5", "and trades its size for the count")
    t.equal(lupine.progress, nil, "the other themes on offer are untouched")
    t.equal(lupine.value, "0.4 MB", "and still say what they cost")
    t.equal(gruvbox.progress, nil, "as is the one already on disk")
    t.equal(gruvbox.value, MenuModel.checkmark, "which still says it is the one in effect")

    // Nothing downloading is the ordinary case, and no row should carry a fraction in it.
    let idle = MenuModel.installableThemes(StyleMenu(themes: [], available: [
        RemoteTheme(slug: "solitude", name: "Solitude", backgrounds: []),
    ]))
    t.equal(idle.compactMap { $0.progress }.count, 0, "with nothing being fetched, no row fills")
}

h.test("choosing a theme leaves the menu up, and everything else dismisses it") { t in
    // Two reasons, pointing the same way: a theme toe has not got is being *fetched*, and the
    // filling row is the only thing reporting it; and a theme recolours the menu itself, so
    // staying put turns the list into something you can look through rather than commit to.
    t.equal(Command.theme("solitude").keepsMenuOpen, true, "a theme to be downloaded stays")
    t.equal(Command.theme("gruvbox").keepsMenuOpen, true, "and so does one already on disk")
    t.equal(Command.theme("").keepsMenuOpen, true,
            "`Your own colours` is the way back, and a way back you must reopen the menu to use "
            + "is not much of one")

    // A wallpaper is behind the panel rather than in it: nothing to restyle, nothing being
    // fetched, and the picture is the whole of what changed.
    t.equal(Command.background("1-a.jpg").keepsMenuOpen, false, "backgrounds still close")
    t.equal(Command.nextBackground.keepsMenuOpen, false, "including stepping through them")
    // The rest want the panel gone and the keyboard handed back before they begin.
    t.equal(Command.quit.keepsMenuOpen, false, "quit tears the process down")
    t.equal(Command.reload.keepsMenuOpen, false, "a reload is over before you could look at it")
    t.equal(Command.exec("ghostty").keepsMenuOpen, false, "an exec brings something else forward")
    t.equal(Command.killActive.keepsMenuOpen, false,
            "and a window command acts on a window you cannot see past the menu")
}

h.test("a filling row is the row cut off at the fraction") { t in
    let m = MenuMetrics(lineHeight: 22)
    let row = MenuLayout.rowFrame(0, width: 400, m)
    t.equalBox(MenuLayout.progressFrame(inRow: row, fraction: 0.5),
               Box(x: row.x, y: row.y, w: row.w / 2, h: row.h),
               "half the row, from its own left edge and its full height")
    t.equalBox(MenuLayout.progressFrame(inRow: row, fraction: 0),
               Box(x: row.x, y: row.y, w: 0, h: row.h), "nothing at nothing")
    t.equalBox(MenuLayout.progressFrame(inRow: row, fraction: 1), row, "and the whole row at one")
    // The fraction comes from arithmetic over a count off the network.
    t.equalBox(MenuLayout.progressFrame(inRow: row, fraction: 4),
               row, "a fraction past one fills the row rather than running out of the panel")
    t.equalBox(MenuLayout.progressFrame(inRow: row, fraction: -1),
               Box(x: row.x, y: row.y, w: 0, h: row.h), "and one below zero draws nothing")
}

h.test("rebuilding under an open menu leaves you where you were standing") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config(),
                                           style: downloadingStyle(fetching: 1, bytesDone: 0)), visibleRows: 10)
    // Down into Install › Style › Theme, the way a user gets to a theme they have not got.
    while m.selectedItem?.title != "Install" { m.move(by: 1) }
    t.equal(m.activate(), .pushed, "into Install")
    while m.selectedItem?.title != "Style" { m.move(by: 1) }
    t.equal(m.activate(), .pushed, "into Style")
    while m.selectedItem?.title != "Theme" { m.move(by: 1) }
    t.equal(m.activate(), .pushed, "and into Theme")
    while m.selectedItem?.title != "Solitude" { m.move(by: 1) }
    let standingOn = m.selection
    t.equal(m.selectedItem?.progress, 0, "the row under the cursor is filling from nothing")

    // A picture lands. The whole tree is rebuilt, because the level in front of the user is two
    // rungs down and the menu cannot know which of MenuModel's builders made it.
    m.rebuild(root: MenuModel.root(loginItem: .off, config: Config(),
                                   style: downloadingStyle(fetching: 5, bytesDone: 2_400_000)))
    t.equal(m.breadcrumb, ["Install", "Style", "Theme"], "still on the level it was on")
    t.equal(m.selection, standingOn, "still on the row it was on")
    t.equal(m.selectedItem?.title, "Solitude", "which is still the same row")
    t.equal(m.selectedItem?.progress, 2_400_000.0 / 4_400_000, "and it has filled further")
    t.equal(m.selectedItem?.value, "5/5", "with the count to match")
}

h.test("a rebuild that cannot re-enter a level surfaces one rung up") { t in
    // Background exists only while the current theme has pictures, so changing to a theme with
    // none takes the level the user is standing in out from under them. Real, not defensive.
    let withPictures = StyleMenu(themes: [ThemeRef(slug: "gruvbox", name: "Gruvbox")],
                                 current: "gruvbox", backgrounds: ["1-a.jpg", "2-b.jpg"])
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config(), style: withPictures),
                      visibleRows: 10)
    while m.selectedItem?.title != "Style" { m.move(by: 1) }
    _ = m.activate()
    while m.selectedItem?.title != "Background" { m.move(by: 1) }
    _ = m.activate()
    t.equal(m.breadcrumb, ["Style", "Background"], "standing in Background")
    t.equal(m.visible.count, 3, "two pictures and the row that steps through them")

    let withNone = StyleMenu(themes: [ThemeRef(slug: "vantablack", name: "Vantablack")],
                             current: "vantablack")
    m.rebuild(root: MenuModel.root(loginItem: .off, config: Config(), style: withNone))
    // Not an error and not an empty level: the deepest level that still exists.
    t.equal(m.breadcrumb, ["Style"], "the level went away, so the user comes up to Style")
    t.equal(m.visible.map(\.title), ["Theme"], "which no longer offers Background at all")
    t.expect(m.selection < m.visible.count, "and the selection is inside the level it landed on")
}

h.test("the fetching note appears and goes away without the menu being reopened") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config(),
                                           style: StyleMenu(fetching: true)),
                      visibleRows: 10, path: ["Install", "Style", "Theme"])
    t.equal(m.visible.map(\.title), ["Fetching Omarchy's themes…"],
            "a machine with nothing yet, mid-fetch")

    // The catalogue arrives. This is what `ThemeCatalogue.onChange` now reaches.
    m.rebuild(root: MenuModel.root(loginItem: .off, config: Config(), style: StyleMenu(
        available: [RemoteTheme(slug: "nord", name: "Nord", backgrounds: [])], fetching: false)))
    t.equal(m.visible.map(\.title), ["Nord"],
            "the note gives way to the themes it was waiting for")
}

h.test("the selection clamps at both ends") { t in
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config()), visibleRows: 10)
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
        .killActive, .toggleFloating, .toggleSplit, .swapSplit, .resizeActive(dx: 100, dy: 0),
        .growActive(dx: 100, dy: 0),
        .exec("open -a Safari"), .reload, .quit,
        .menu(.root), .menu(.keybindings), .menu(.theme), .menu(.background),
        .theme("gruvbox"), .theme(""), .removeTheme("gruvbox"),
        .background("city.jpg"), .nextBackground,
    ]
    for command in all {
        let label = CommandLabel.describe(command)
        t.expect(!label.isEmpty, "\(command) has a label")
        t.expect(label.first?.isUppercase == true, "\(command)'s label is prose, not a case name")
    }
    t.equal(CommandLabel.describe(.moveFocus(.left)), "Move focus left", "a sample of the prose")
    t.equal(CommandLabel.describe(.menu(.keybindings)), "Show the keybindings", "and the new one")
    t.equal(CommandLabel.describe(.menu(.theme)), "Open Style › Theme",
            "a route is named by the level it opens, so the label cannot drift from the menu")
    t.equal(CommandLabel.describe(.removeTheme("rose-pine")), "Remove the theme Rose Pine",
            "and removing one reads as what it does to the disk")
    t.equal(CommandLabel.describe(.theme("gruvbox")), "Theme: Gruvbox",
            "a theme toe ships is named the way it names itself")
    t.equal(CommandLabel.describe(.theme("rose-pine")), "Theme: Rose Pine",
            "and one of yours is titled from its directory, which is all it has")
    t.equal(CommandLabel.describe(.theme("")), "Use your own colours",
            "clearing the theme reads as what it does, not as an empty name")
    t.equal(CommandLabel.describe(.nextBackground), "Next background", "and the cycle")
    t.equal(CommandLabel.describe(.resizeActive(dx: 100, dy: 0)), "Move the split 100 pt right",
            "a resize names where the split goes — the window's fate depends on which side you are on")
    t.equal(CommandLabel.describe(.resizeActive(dx: 0, dy: -100)), "Move the split 100 pt up", "and up")
    t.equal(CommandLabel.describe(.resizeActive(dx: 100, dy: 50)),
            "Move the splits 100 pt right and 50 pt down", "both axes, both named")
    t.equal(CommandLabel.describe(.growActive(dx: 100, dy: 0)), "Make the window 100 pt wider",
            "growactive names what happens to the window, which is the whole of its meaning")
    t.equal(CommandLabel.describe(.growActive(dx: 0, dy: -100)), "Make the window 100 pt shorter", "and shorter")
    t.equal(CommandLabel.describe(.growActive(dx: -100, dy: 50)),
            "Make the window 100 pt narrower and 50 pt taller", "both axes")
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
            "and it is the binding the menu offers as Config")
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
             "an unknown route is an error rather than quietly the root menu")
}

h.test("a menu binding opens the level Omarchy's own key opens") { t in
    // The routes are `omarchy-menu toggle <route>`, aliases included, so a line copied out of
    // Omarchy's bindings opens the same level here.
    t.equal(try CommandParser.parse("menu theme"), .menu(.theme), "SUPER+SHIFT+CTRL+SPACE's")
    t.equal(try CommandParser.parse("menu themes"), .menu(.theme), "and upstream's plural alias")
    t.equal(try CommandParser.parse("menu background"), .menu(.background), "SUPER+CTRL+SPACE's")
    t.equal(try CommandParser.parse("menu wallpaper"), .menu(.background), "by its other name")
    t.equal(try CommandParser.parse("menu settings"), .menu(.setup),
            "Omarchy's alias for Setup, which is the name it gives the level")
    t.equal(try CommandParser.parse("menu uninstall"), .menu(.remove), "and for Remove")
    t.equal(try CommandParser.parse("menu install"), .menu(.install), "the level itself")
    t.equal(MenuRoute.theme.path, ["Style", "Theme"], "a route is a path through the tree")

    t.equal(try CommandParser.parse("removetheme gruvbox"), .removeTheme("gruvbox"),
            "removing one is a command like any other")
    t.equal(try CommandParser.parse("removetheme \"Rose Pine\""), .removeTheme("rose-pine"),
            "slugified at the door, because the name is about to be joined onto a path")
    t.expect((try? CommandParser.parse("removetheme")) == nil,
             "and it needs an argument — there is no theme called nothing to delete")
}

h.test("resizeactive takes Hyprland's two numbers and nothing else") { t in
    t.equal(try CommandParser.parse("resizeactive 100 0"), .resizeActive(dx: 100, dy: 0), "plain")
    t.equal(try CommandParser.parse("resizeactive, -100 0"), .resizeActive(dx: -100, dy: 0),
            "Hyprland's comma after the verb")
    t.equal(try CommandParser.parse("resizeactive 0, 100"), .resizeActive(dx: 0, dy: 100),
            "or between the numbers")
    t.expect((try? CommandParser.parse("resizeactive")) == nil, "it needs an argument")
    t.expect((try? CommandParser.parse("resizeactive 100")) == nil, "two of them")
    t.expect((try? CommandParser.parse("resizeactive exact 100 100")) == nil,
             "and not Hyprland's exact form: a tile's size is the tree's to decide")
    t.expect((try? CommandParser.parse("resizeactive 10% 0")) == nil, "nor a percentage")
    t.expect((try? CommandParser.parse("resizeactive 1e309 0")) == nil, "nor a number that overflowed")
    t.equal(try CommandParser.parse("growactive 100 0"), .growActive(dx: 100, dy: 0),
            "growactive takes the same two numbers, meaning the window rather than the split")
    t.expect((try? CommandParser.parse("growactive 100")) == nil, "and is as strict about them")
}

// MARK: - Themes

/// Omarchy's themes/tokyo-night/colors.toml, verbatim. Pasted rather than summarised, because
/// what is being asserted is that toe reads *their* file — a paraphrase would pass while the real
/// thing failed.
let tokyoNightColors = """
accent = "#7aa2f7"
cursor = "#c0caf5"
foreground = "#a9b1d6"
background = "#1a1b26"
selection_foreground = "#c0caf5"
selection_background = "#7aa2f7"

color0 = "#32344a"
color1 = "#f7768e"
color2 = "#9ece6a"
color3 = "#e0af68"
color4 = "#7aa2f7"
color5 = "#ad8ee6"
color6 = "#449dab"
color7 = "#787c99"
color8 = "#444b6a"
color9 = "#ff7a93"
color10 = "#b9f27c"
color11 = "#ff9e64"
color12 = "#7da6ff"
color13 = "#bb9af7"
color14 = "#0db9d7"
color15 = "#acb0d0"
"""

/// The same theme, in the spelling Omarchy 4 publishes it in — `themes/tokyo-night/colors.toml`
/// on the `quattro` branch, verbatim. Held beside the Omarchy 3 file above rather than replacing
/// it, because both are files toe has to read: this one is what a download fetches today, and
/// that one is what is already sitting in `~/.config/toe/themes` on the disk of anybody who
/// copied a theme across before Omarchy 4.
let tokyoNightColors4 = """
mode = "dark"

accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"

background = "#1a1b26"
dark_background = "#13141c"
darker_background = "#0e0e14"
lighter_background = "#24283b"

foreground = "#a9b1d6"
dark_foreground = "#565f89"
light_foreground = "#b4bee6"
bright_foreground = "#c0caf5"

red = "#f7768e"
yellow = "#e0af68"
orange = "#eb927b"
green = "#9ece6a"
cyan = "#449dab"
blue = "#7aa2f7"
magenta = "#ad8ee6"
brown = "#75493d"

bright_red = "#ff7a93"
bright_yellow = "#ff9e64"
bright_green = "#b9f27c"
bright_cyan = "#0db9d7"
bright_blue = "#7da6ff"
bright_magenta = "#bb9af7"
"""

/// Two themes to test against, built here rather than taken from toe. toe ships none: a theme is
/// somebody else's work, and the list you choose from is what you have on disk plus what Omarchy
/// publishes. So the fixtures below are exactly that — a theme somebody downloaded.
let tokyoNight = Theme(slug: "tokyo-night", name: "Tokyo Night",
                       palette: try! Palette.parse(tokyoNightColors))
let gruvbox = Theme(slug: "gruvbox", name: "Gruvbox",
                    palette: Palette(accent: "#7daea3", background: "#282828",
                                     foreground: "#d4be98"))

h.test("an Omarchy colors.toml is read key for key") { t in
    guard let p = try? Palette.parse(tokyoNightColors) else {
        return t.expect(false, "the shipped Tokyo Night palette should parse")
    }
    t.equal(p.accent, "#7aa2f7", "accent is what the border takes")
    t.equal(p.background, "#1a1b26", "background is walker's @base")
    t.equal(p.foreground, "#a9b1d6", "foreground is walker's @text")
    t.equal(p.cursor, "#c0caf5", "the keys toe does not paint with are kept anyway")
    t.equal(p.color(6), "#449dab", "color0…color15 land in order")
    t.equal(p.color(15), "#acb0d0", "including the last one")
    t.equal(p.color(16), nil, "and nothing past it")
    t.equal(p.terminal.compactMap { $0 }.count, 16, "all sixteen terminal colours land")
}

h.test("a theme missing a colour toe paints with is refused rather than guessed at") { t in
    t.equal(try? Palette.parse("background = \"#000000\"\nforeground = \"#ffffff\"") , nil,
            "no accent is not a theme")
    do {
        _ = try Palette.parse("background = \"#000000\"\nforeground = \"#ffffff\"")
        t.expect(false, "it should have thrown")
    } catch {
        t.equal(error as? PaletteError, .missing("accent"), "and it names the key that is absent")
    }
    do {
        _ = try Palette.parse("accent = \"blue\"\nbackground = \"#000\"\nforeground = \"#fff\"")
        t.expect(false, "it should have thrown")
    } catch {
        t.equal(error as? PaletteError, .notAColour(key: "accent", value: "blue"),
                "a colour that will not parse is named with what was there, as Hex.rgba's nil intends")
    }
}

h.test("Omarchy 4's colors.toml is read too, key for key") { t in
    guard let p = try? Palette.parse(tokyoNightColors4) else {
        return t.expect(false, "the Omarchy 4 Tokyo Night palette should parse")
    }
    // The three toe paints with are spelled the same in both files, and for this theme they carry
    // the same values too — so following the new branch left Tokyo Night's border alone. It is
    // not true of every theme: Kanagawa's accent changed upstream between the two, which is an
    // Omarchy edit rather than anything this parser does.
    t.equal(p.accent, "#7aa2f7", "accent is still accent")
    t.equal(p.background, "#1a1b26", "as is background")
    t.equal(p.foreground, "#a9b1d6", "and foreground")

    t.equal(p.mode, .dark, "and mode is read, which Omarchy 3 never said")
    t.equal(p.darkerBackground, "#0e0e14", "the background ramp lands, darkest first")
    t.equal(p.darkBackground, "#13141c", "then dark")
    t.equal(p.lighterBackground, "#24283b", "then lighter")
    t.equal(p.darkForeground, "#565f89", "and the foreground ramp with it")
    t.equal(p.lightForeground, "#b4bee6", "light")
    t.equal(p.brightForeground, "#c0caf5", "and bright")
    t.equal(p.selection, "#292e42", "selection replaces the selection_* pair")
    t.equal(p.muted, "#414868", "and muted beside it")

    // Two hues with no ANSI slot to live in, which is the whole reason they are stored by name.
    t.equal(p.orange, "#eb927b", "orange has no terminal slot and is kept anyway")
    t.equal(p.brown, "#75493d", "nor does brown")

    // Nothing in Omarchy 4's file means any of these, and a nil is the honest answer.
    t.equal(p.cursor, nil, "cursor is gone from the format, not defaulted to something")
    t.equal(p.selectionForeground, nil, "and the keys it replaced are not invented back")
    t.equal(p.selectionBackground, nil, "either of them")
}

h.test("a named hue and a numbered slot are the same colour under two names") { t in
    guard let three = try? Palette.parse(tokyoNightColors),
          let four = try? Palette.parse(tokyoNightColors4) else {
        return t.expect(false, "both spellings of Tokyo Night should parse")
    }
    // The mapping in `Palette.ansiNames` is only allowed to exist because this holds — checked
    // here on the one theme, and checked against all nineteen that exist on both of Omarchy's
    // branches before it was written down.
    for index in Palette.ansiNames.keys.sorted() {
        t.equal(four.color(index), three.color(index),
                "color\(index) is the same colour whichever file it came from")
    }
    t.equal(four.red, three.color(1), "and red is reachable under its own name")
    t.equal(four.brightCyan, three.color(14), "as is bright_cyan")
    t.equal(four.blue, four.accent, "Tokyo Night's accent is its blue, in both")

    // ANSI's black and white ends have no Omarchy 4 key at all. `muted` and `lighter_background`
    // sit near them in some themes and nowhere near them in most, so the slots stay empty: a
    // caller can fall back from a nil and cannot fall back from a wrong colour.
    for index in [0, 7, 8, 15] {
        t.equal(four.color(index), nil, "slot \(index) has no Omarchy 4 key and is left empty")
        t.expect(three.color(index) != nil, "though Omarchy 3 filled it")
    }
    t.equal(four.terminal.compactMap { $0 }.count, 12, "twelve of the sixteen land")
    t.equal(three.terminal.compactMap { $0 }.count, 16, "against all sixteen from the older file")
}

h.test("a numbered slot wins over the named hue where a file has both") { t in
    // A hand-written palette, or one caught mid-conversion. `color1` names the slot; `red` names
    // a colour that usually sits in it, so the slot is the more specific of the two.
    let both = """
    accent = "#111111"
    background = "#222222"
    foreground = "#333333"
    color1 = "#aaaaaa"
    red = "#bbbbbb"
    """
    guard let p = try? Palette.parse(both) else {
        return t.expect(false, "it should parse")
    }
    t.equal(p.color(1), "#aaaaaa", "the numbered slot is the one that lands")
    t.equal(p.red, "#aaaaaa", "and reading it by name gives the same answer")
}

h.test("a theme's Hyprland overrides are left alone rather than read as colours") { t in
    // `hackerman` carries this, and it is a Hyprland gradient rather than a colour. It is also
    // the most tempting key in the file — literally the border colour — which is why the test
    // exists: reading it would throw `notAColour` and take the theme down with it.
    let hackerman = """
    accent = "#82FB9C"
    background = "#0B0C16"
    foreground = "#ddf7ff"
    hyprland_active_border = "rgba(26a269ee) rgba(2ec27eee) 45deg"
    hyprland_inactive_border = "rgb(1e1e1e)"
    active_border_color = "#f2fcff"
    active_tab_background = "#6fb8e3"
    """
    guard let p = try? Palette.parse(hackerman) else {
        return t.expect(false, "a theme with per-app overrides in it should still parse")
    }
    t.equal(p.accent, "#82FB9C", "the accent is read, uppercase hex and all")
    t.equal(p.colours.contains { $0.key.hasPrefix("hyprland_") }, false,
            "and Hyprland's own keys are not among the colours toe carries")
}

h.test("a mode toe does not recognise leaves the theme usable") { t in
    // Not an error: `mode` is not a colour, nothing paints with it yet, and a third value
    // arriving upstream should widen what toe knows rather than stop a theme from loading.
    let odd = """
    mode = "sepia"
    accent = "#111111"
    background = "#222222"
    foreground = "#333333"
    """
    guard let p = try? Palette.parse(odd) else {
        return t.expect(false, "it should still parse")
    }
    t.equal(p.mode, nil, "the mode is simply not known")
    t.equal(p.accent, "#111111", "and the colours are all still there")
}

// MARK: - The catalogue

/// A cut-down GitHub tree listing, in the shape the real one comes back in. Everything awkward is
/// in here on purpose: a theme with no palette, a directory that is not a slug, a file that is not
/// a picture, and a name that must never reach the filesystem.
let treeJSON = Data("""
{"sha":"x","truncated":false,"tree":[
  {"path":"themes","mode":"040000","type":"tree","sha":"a"},
  {"path":"themes/gruvbox","mode":"040000","type":"tree","sha":"b"},
  {"path":"themes/gruvbox/colors.toml","mode":"100644","type":"blob","sha":"c","size":511},
  {"path":"themes/gruvbox/backgrounds/1-the-backwater.jpg","mode":"100644","type":"blob","sha":"d","size":4127598},
  {"path":"themes/gruvbox/backgrounds/5-leaves.jpg","mode":"100644","type":"blob","sha":"e","size":443959},
  {"path":"themes/gruvbox/README.md","mode":"100644","type":"blob","sha":"f","size":10},
  {"path":"themes/tokyo-night/colors.toml","mode":"100644","type":"blob","sha":"g","size":500},
  {"path":"themes/tokyo-night/backgrounds/0-winding-road.webp","mode":"100644","type":"blob","sha":"h","size":653482},
  {"path":"themes/tokyo-night/backgrounds/.DS_Store","mode":"100644","type":"blob","sha":"i","size":6148},
  {"path":"themes/tokyo-night/backgrounds/omarchy.webp","mode":"100644","type":"blob","sha":"m","size":716},
  {"path":"themes/gruvbox/backgrounds/omarchy.png","mode":"100644","type":"blob","sha":"n","size":900},
  {"path":"themes/no-palette/backgrounds/x.jpg","mode":"100644","type":"blob","sha":"j","size":1},
  {"path":"themes/Not A Slug/colors.toml","mode":"100644","type":"blob","sha":"k","size":1},
  {"path":"bin/omarchy-theme-set","mode":"100755","type":"blob","sha":"l","size":900}
]}
""".utf8)

h.test("one request describes every theme Omarchy publishes") { t in
    guard let c = try? Catalogue.parse(treeJSON) else {
        return t.expect(false, "the tree listing should parse")
    }
    // A theme with no colors.toml is not one toe can use: Omarchy has a few that describe
    // themselves only through per-app templates, and toe renders none of those.
    t.equal(c.themes.map(\.slug), ["gruvbox", "tokyo-night"],
            "themes with a palette, in a stable order, and nothing outside themes/")
    t.equal(c.themes.first?.name, "Gruvbox", "titled from the directory name")
    t.equal(c.themes.first?.backgrounds.map(\.name), ["1-the-backwater.jpg", "5-leaves.jpg"],
            "pictures only — a README beside them is not one")
    t.equal(c.themes.last?.backgrounds.map(\.name), ["0-winding-road.webp"],
            "and neither is the .DS_Store that every folder collects")
    // Every theme upstream carries the OMARCHY wordmark in its backgrounds folder, under one of
    // two extensions. It is not a wallpaper anybody wants on a toe desktop, so it is not fetched
    // and does not count towards what the row says a theme costs.
    t.equal(c.themes.flatMap { $0.backgrounds.map(\.name) }.contains { $0.hasPrefix("omarchy.") },
            false, "and the wordmark is left where it is")
    // The size is what the menu row shows, and the whole reason this shape was chosen over one
    // request per theme.
    t.equal(c.themes.first?.bytes, 4127598 + 443959,
            "a theme knows what it costs to download, the wordmark excluded")
    t.equal(ByteSize.describe(c.themes.first?.bytes ?? 0), "4.4 MB", "as the row says it")
}

h.test("upstream's wordmark is not fetched, but yours is still listed") { t in
    for name in ["omarchy.png", "omarchy.webp", "OMARCHY.PNG"] {
        t.equal(Backgrounds.isUpstreamBranding(name), true, "\(name) is branding, not a wallpaper")
    }
    for name in ["1-the-backwater.jpg", "omarchy-cityscape.jpg", "my-omarchy.png"] {
        t.equal(Backgrounds.isUpstreamBranding(name), false, "\(name) is not")
    }
    // Filtered where a theme is fetched, not where a folder is listed: declining to download
    // another project's wordmark is toe's call, and overruling a file you put there yourself is
    // not.
    t.equal(Backgrounds.list(["omarchy.png", "a.jpg"]), ["a.jpg", "omarchy.png"],
            "a folder you assembled by hand is shown whole")
}

h.test("a directory that is not a slug is not a theme") { t in
    guard let c = try? Catalogue.parse(treeJSON) else {
        return t.expect(false, "the tree listing should parse")
    }
    // `Not A Slug` has a colors.toml and is still refused. This name would become a directory
    // under ~/.config/toe/themes, and a path component is the only thing it is allowed to be.
    t.equal(c.themes.contains { $0.name.contains("Not A Slug") }, false, "refused, not repaired")
    t.equal(c.themes.count, 2, "and it is not silently slugified into one either")
}

h.test("a listing that came back incomplete is refused outright") { t in
    // GitHub truncates a tree too large to serve. Half a catalogue is worse than none: it would
    // look complete, and the themes missing from it would look as though they did not exist.
    let truncated = Data(#"{"truncated":true,"tree":[]}"#.utf8)
    do { _ = try Catalogue.parse(truncated); t.expect(false, "it should have thrown") }
    catch { t.equal(error as? CatalogueError, .truncated, "and says so") }

    do { _ = try Catalogue.parse(Data("not json".utf8)); t.expect(false, "it should have thrown") }
    catch { t.equal(error as? CatalogueError, .notJSON, "as does a body that is not JSON at all") }

    do { _ = try Catalogue.parse(Data(#"{"tree":[]}"#.utf8)); t.expect(false, "it should have thrown") }
    catch { t.equal(error as? CatalogueError, .empty, "and one with no themes in it") }
}

h.test("a name off the network is checked by shape, not searched for tricks") { t in
    // A whitelist, because "does not contain .." is the kind of rule that is one encoding trick
    // away from being wrong. These names are about to be joined onto a directory path.
    for bad in ["", ".", "..", "../evil", "a/b", "a\\b", ".hidden", String(repeating: "z", count: 200)] {
        t.equal(Catalogue.isSafeFileName(bad), false, "'\(bad)' is not a name toe will write")
    }
    for good in ["1-the-backwater.jpg", "0-winding-road.webp", "a b c.png"] {
        t.equal(Catalogue.isSafeFileName(good), true, "'\(good)' is")
    }
}

h.test("a catalogue goes stale, and a clock that jumped reads as stale too") { t in
    let now = Date()
    let fresh = Catalogue(fetchedAt: now.addingTimeInterval(-60), themes: [])
    t.equal(fresh.isStale(now: now, maxAge: 3600), false, "a minute old is fresh")
    t.equal(fresh.isStale(now: now, maxAge: 30), true, "and past the age it is not")
    // A restored machine or a corrected clock can put the stamp in the future. Refetching is the
    // cheap answer; treating it as fresh would wedge the list until the skew passed.
    let future = Catalogue(fetchedAt: now.addingTimeInterval(3600), themes: [])
    t.equal(future.isStale(now: now, maxAge: 86400), true, "a stamp in the future is not fresh")
}

h.test("a catalogue written before the move to Omarchy 4 is not mistaken for a current one") { t in
    // The real shape of a stale one, cut down from a catalogue.json this machine had actually
    // written against Omarchy's `master` branch. What makes it unusable is not its age: the
    // pictures it names were renamed when Omarchy 4 re-encoded them, so downloading White from
    // this listing would ask for `1-white.jpg` and get a 404 partway through.
    let old = Data("""
    {"version":1,"fetchedAt":"2026-09-03T12:15:55Z","themes":[
      {"slug":"white","name":"White","backgrounds":[{"name":"1-white.jpg","bytes":1229622}]}
    ]}
    """.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let decoded = try? decoder.decode(Catalogue.self, from: old) else {
        return t.expect(false, "an old catalogue should still decode — it is refused, not unreadable")
    }
    t.equal(decoded.version, 1, "it reads back as the version it was written at")
    t.expect(decoded.version != Catalogue.currentVersion,
             "which is not the current one, so ThemeCatalogue.load discards it and refetches")
    // Stated as the number rather than just "not current", so that a future bump has to come
    // past this line and say what it is invalidating.
    t.equal(Catalogue.currentVersion, 2, "2 since the move from master to quattro")

    // A catalogue toe wrote itself is current by construction — the bump must not be reachable
    // by forgetting to set the field.
    t.equal(Catalogue(fetchedAt: Date(), themes: []).version, Catalogue.currentVersion,
            "and a freshly built one is always current")
}

h.test("a byte count reads the way a menu row needs it to") { t in
    t.equal(ByteSize.describe(4571557), "4.4 MB", "megabytes to one place")
    t.equal(ByteSize.describe(330000), "0.3 MB", "including under one")
    t.equal(ByteSize.describe(511), "1 KB", "and kilobytes below that")
    t.equal(ByteSize.describe(0), "", "nothing at all for nothing")
}

// MARK: - Themes

h.test("a theme name is slugified the way Omarchy slugifies it") { t in
    t.equal(Slug.make("Tokyo Night"), "tokyo-night", "lowercased, spaces to hyphens")
    t.equal(Slug.make("CATPPUCCIN"), "catppuccin", "however it was shouted")
    t.equal(Slug.make("rose_pine"), "rose-pine", "an underscore is a hyphen")
    t.equal(Slug.make("Rose  Pine"), "rose-pine", "and runs collapse")
    t.equal(Slug.make("  gruvbox  "), "gruvbox", "trimmed at both ends")
    t.equal(Slug.make(""), "", "nothing stays nothing — that is how a theme is cleared")
    // The reason the filter exists: this value becomes a path component under
    // ~/.config/toe/themes AND a string literal inside the user's own config.
    t.equal(Slug.make("../../.ssh"), "ssh", "a path cannot be walked out of")
    t.equal(Slug.make("/etc/passwd"), "etcpasswd", "and a leading slash is not a slug character")
    t.equal(Slug.make("a\" b [x]"), "a-b-x", "nor is a quote or a bracket")
    t.expect(Slug.make(String(repeating: "z", count: 200)).count <= 64, "and it cannot run away")
}

h.test("a directory name reads back as a title") { t in
    t.equal(Slug.title("catppuccin-latte"), "Catppuccin Latte", "hyphens are spaces again")
    t.equal(Slug.title("gruvbox"), "Gruvbox", "one word is capitalised")
    t.equal(Slug.title(""), "", "and nothing is nothing")
}

h.test("a theme you have is listed and dimmed rather than offered twice") { t in
    let installed = [ThemeRef(slug: "rose-pine", name: "Rose Pine"),
                     ThemeRef(slug: "gruvbox", name: "Gruvbox")]
    let available = [RemoteTheme(slug: "gruvbox", name: "Gruvbox", backgrounds: []),
                     RemoteTheme(slug: "nord", name: "Nord",
                                 backgrounds: [RemoteFile(name: "a.jpg", bytes: 4_300_000)])]
    t.equal(Themes.ordered(installed).map(\.slug), ["gruvbox", "rose-pine"],
            "yours, sorted by name — the order every level that lists them draws")

    // Omarchy's `disabled` guard: Install stays a catalogue of everything it can fetch rather
    // than a list that gets shorter every time you use it.
    let rows = MenuModel.installableThemes(StyleMenu(themes: installed, available: available))
    t.equal(rows.map(\.title), ["Gruvbox", "Nord"], "the whole catalogue, in its own order")
    t.equal(rows.map(\.isDisabled), [true, false], "and the one you have cannot be fetched again")
    t.equal(rows.first?.value, MenuModel.checkmark, "which is what the tick says")
    t.equal(rows.last?.value, "4.1 MB", "while the one you could have says what it costs")

    let fresh = MenuModel.installableThemes(StyleMenu(themes: [], available: available))
    t.equal(fresh.map(\.isDisabled), [false, false],
            "a machine that has fetched nothing is offered everything")
}

h.test("toe's own colours are Tokyo Night already, so that theme only moves the border") { t in
    guard let c = try? Config.parse(Config.defaultTOML) else {
        return t.expect(false, "the shipped config parses")
    }
    let themed = c.applying(tokyoNight)
    // The payoff, and the reason a fresh install with no themes at all still looks themed:
    // MenuConfig's defaults were derived from this very palette through walker's token mapping,
    // so applying Tokyo Night must be a no-op on the menu. If this fails, one of the two drifted.
    t.equal(themed.menu, c.menu, "the menu is already Tokyo Night, to the byte")
    t.equal(themed.border.activeStart, "#7aa2f7", "and the border takes the accent")
    t.equal(themed.border.activeEnd, "#7aa2f7", "at both stops")
    t.equal(themed.theme.name, "tokyo-night", "the resolved slug is what the menu marks with")
}

h.test("a theme takes both border stops, because Omarchy's border is flat") { t in
    let c = Config()
    for theme in [tokyoNight, gruvbox] {
        let themed = c.applying(theme)
        t.equal(themed.border.activeStart, theme.palette.accent, "\(theme.slug) start")
        t.equal(themed.border.activeEnd, theme.palette.accent, "\(theme.slug) end")
        t.equal(themed.menu.background, theme.palette.background, "\(theme.slug) menu background")
        t.equal(themed.menu.foreground, theme.palette.foreground, "\(theme.slug) menu foreground")
        t.equal(themed.menu.accent, theme.palette.accent, "\(theme.slug) menu accent")
        t.equal(themed.menu.border, nil, "\(theme.slug) rejoins the border to the foreground")
    }
}

h.test("a theme leaves every size and behaviour alone") { t in
    guard let c = try? Config.parse(Config.defaultTOML) else {
        return t.expect(false, "the shipped config parses")
    }
    let themed = c.applying(gruvbox)
    t.equal(themed.border.width, c.border.width, "border width")
    t.equal(themed.border.angle, c.border.angle, "the sweep angle survives, inert, for when the theme is cleared")
    t.equal(themed.border.radius, c.border.radius, "corner radius")
    t.equal(themed.border.enabled, c.border.enabled, "and whether there is a border at all")
    t.equal(themed.menu.opacity, c.menu.opacity, "menu opacity")
    t.equal(themed.menu.width, c.menu.width, "menu width")
    t.equal(themed.menu.listWidth, c.menu.listWidth, "list width")
    t.equal(themed.menu.fontSize, c.menu.fontSize, "font size")
    t.equal(themed.bindings.count, c.bindings.count, "and it is not a config reload")
}

h.test("the theme wins over the colour keys, and says nothing about it") { t in
    let text = """
    [theme]
    name = "gruvbox"

    [border]
    active_start = "#111111"
    active_end   = "#222222"

    [menu]
    background = "#333333"
    """
    guard let c = try? Config.parse(text) else { return t.expect(false, "it parses") }
    t.equal(c.border.activeStart, "#111111", "parse reads the file as written")
    let themed = c.applying(gruvbox)
    t.equal(themed.border.activeStart, "#7daea3", "and applying overrules it outright")
    t.equal(themed.menu.background, "#282828", "menu colours too")
    // Not a merge and not a warning: the config toe ships sets all of these, so a warning here
    // would fire for everybody the first time they picked a theme.
    t.equal(c.warnings, [], "and nothing is warned about")
}

h.test("no theme is today's behaviour, exactly") { t in
    guard let c = try? Config.parse(Config.defaultTOML) else {
        return t.expect(false, "the shipped config parses")
    }
    t.equal(c.theme.name, "", "the shipped config names no theme")
    t.equal(c.border.activeStart, "#33ccffee", "so the gradient is untouched")
    t.equal(c.border.activeEnd, "#00ff99ee", "at both ends")
}

h.test("a theme name that is not a name is refused rather than used") { t in
    guard let c = try? Config.parse("[theme]\nname = 3\n") else {
        return t.expect(false, "it still parses")
    }
    t.equal(c.theme.name, "", "a number is not a theme")
    t.expect(c.warnings.contains { $0.contains("theme.name") }, "and it is named in the tooltip")
}

// MARK: - Writing the theme back

h.test("setting a theme moves one line and leaves every other byte") { t in
    let before = Config.defaultTOML
    let after = ThemeWriter.settingTheme("gruvbox", in: before)
    let a = before.components(separatedBy: "\n"), b = after.components(separatedBy: "\n")
    t.equal(a.count, b.count, "no line is added or removed")
    let changed = zip(a, b).filter { $0 != $1 }
    t.equal(changed.count, 1, "and exactly one is different")
    guard let c = try? Config.parse(after) else { return t.expect(false, "the result parses") }
    t.equal(c.theme.name, "gruvbox", "as the theme that was asked for")
    t.equal(c.warnings, [], "with nothing to warn about")
}

h.test("a boolean is written back the way a theme is") { t in
    let before = Config.defaultTOML
    let after = ConfigWriter.setting("slide_on_swipe", to: "true", inTable: "animations", of: before)
    let a = before.components(separatedBy: "\n"), b = after.components(separatedBy: "\n")
    t.equal(a.count, b.count, "no line is added or removed")
    t.equal(zip(a, b).filter { $0 != $1 }.count, 1, "and exactly one is different")
    guard let c = try? Config.parse(after) else { return t.expect(false, "the result parses") }
    t.equal(c.animations.slideOnSwipe, true, "the slide is on")
    t.equal(c.warnings, [], "with nothing to warn about")
    t.equal(ConfigWriter.setting("slide_on_swipe", to: "false", inTable: "animations", of: after),
            before, "and off again is the shipped file, byte for byte")

    let bare = ConfigWriter.setting("slide_on_swipe", to: "true", inTable: "animations",
                                    of: "[general]\ngaps_in = 5\n")
    t.equal(try? Config.parse(bare).animations.slideOnSwipe, true, "a config without the table grows it")
    t.equal(try? Config.parse(bare).gaps.inner, 5, "and keeps what it had")
}

h.test("a config written before themes existed grows the table at the end") { t in
    for source in ["[general]\ngaps_in = 5\n", "[general]\ngaps_in = 5"] {
        let after = ThemeWriter.settingTheme("catppuccin", in: source)
        guard let c = try? Config.parse(after) else {
            return t.expect(false, "it parses whether or not the file ended in a newline")
        }
        t.equal(c.theme.name, "catppuccin", "the theme is set")
        t.equal(c.gaps.inner, 5, "and what was already there is still there")
    }
    t.equal(try? Config.parse(ThemeWriter.settingTheme("gruvbox", in: "")).theme.name, "gruvbox",
            "an empty file is a config with only a theme in it")
}

h.test("a name key in another table is not the theme's") { t in
    let source = """
    [theme]
    name = "tokyo-night"

    [[float]]
    app = "com.apple.finder"
    title = "Copy"
    """
    let after = ThemeWriter.settingTheme("gruvbox", in: source)
    guard let c = try? Config.parse(after) else { return t.expect(false, "it parses") }
    t.equal(c.theme.name, "gruvbox", "the theme moved")
    t.expect(after.contains("app = \"com.apple.finder\""), "and the float rule did not")
    // A `name` before any header at all is the root table, which is not [theme] either.
    let rooted = ThemeWriter.settingTheme("gruvbox", in: "name = \"keep me\"\n[theme]\nname = \"x\"\n")
    t.expect(rooted.hasPrefix("name = \"keep me\""), "a key above every header is left alone")
}

h.test("a comment beside the theme name survives being retuned") { t in
    let after = ThemeWriter.settingTheme("gruvbox", in: "[theme]\nname   = \"tokyo-night\"   # mine\n")
    t.equal(after, "[theme]\nname   = \"gruvbox\"   # mine\n",
            "the alignment and the comment are both the user's, not ours")
}

h.test("a theme table with no name in it yet gains one") { t in
    let after = ThemeWriter.settingTheme("gruvbox", in: "[theme]\n# nothing here yet\n[border]\nwidth = 2\n")
    guard let c = try? Config.parse(after) else { return t.expect(false, "it parses") }
    t.equal(c.theme.name, "gruvbox", "inserted under the header it belongs to")
    t.equal(c.border.width, 2, "and not in the table below it")
}

h.test("clearing the theme is setting it to nothing") { t in
    let after = ThemeWriter.settingTheme("", in: "[theme]\nname = \"gruvbox\"\n")
    t.equal(after, "[theme]\nname = \"\"\n", "which is what hands your own colours back")
}

h.test("setting the same theme twice writes the same bytes") { t in
    let once = ThemeWriter.settingTheme("gruvbox", in: Config.defaultTOML)
    t.equal(ThemeWriter.settingTheme("gruvbox", in: once), once, "so a repeat is not a file change")
}

h.test("a config saved with Windows line endings keeps them") { t in
    let source = "[theme]\r\nname = \"tokyo-night\"\r\n[border]\r\nwidth = 2\r\n"
    let after = ThemeWriter.settingTheme("gruvbox", in: source)
    t.equal(after, "[theme]\r\nname = \"gruvbox\"\r\n[border]\r\nwidth = 2\r\n",
            "TOML.parse normalises CRLF on the way in; writing a file back must not")
    t.equal(try? Config.parse(after).theme.name, "gruvbox", "and it still parses")
    // Asserted whole rather than with `contains`, which passed while the writer was emitting
    // "\n\r" — the carriage return landing at the head of the next line instead of the tail of
    // its own, leaving a stray CR in a file this is meant to preserve byte for byte.
    t.equal(ThemeWriter.settingTheme("gruvbox", in: "[general]\r\ngaps_in = 5\r\n"),
            "[general]\r\ngaps_in = 5\r\n\r\n[theme]\r\nname = \"gruvbox\"\r\n",
            "a table appended to a CRLF file is CRLF throughout, and nothing else is")
    t.equal(ThemeWriter.settingTheme("gruvbox", in: "[general]\r\ngaps_in = 5"),
            "[general]\r\ngaps_in = 5\r\n\r\n[theme]\r\nname = \"gruvbox\"\r\n",
            "including when the file did not end in one")
    t.equal(ThemeWriter.settingTheme("gruvbox", in: "[general]\ngaps_in = 5\n"),
            "[general]\ngaps_in = 5\n\n[theme]\nname = \"gruvbox\"\n",
            "and a Unix file gains no carriage returns from having the option")
}

h.test("a header is still the theme table however it is spelled") { t in
    for header in ["[theme]", "[ theme ]", "[\"theme\"]"] {
        let after = ThemeWriter.settingTheme("gruvbox", in: "\(header)\nname = \"x\"\n")
        t.equal(try? Config.parse(after).theme.name, "gruvbox", "\(header) is the theme table")
    }
    // A header inside a comment is not a header.
    let commented = ThemeWriter.settingTheme("gruvbox", in: "# [theme]\nname = \"keep\"\n")
    t.expect(commented.contains("name = \"keep\""), "a commented-out header opens nothing")
}

h.test("a theme name can never break the file it is written into") { t in
    let hostile = ThemeWriter.settingTheme("a\" b [x]\nname = \"evil", in: Config.defaultTOML)
    guard let c = try? Config.parse(hostile) else {
        return t.expect(false, "whatever went in, what comes out is a config")
    }
    t.equal(c.theme.name, "a-b-x-name-evil", "because a slug has no quote, bracket or newline in it")
}

h.test("the theme commands parse in Omarchy's spellings") { t in
    t.equal(try? CommandParser.parse("theme gruvbox"), .theme("gruvbox"), "plain")
    t.equal(try? CommandParser.parse("theme, gruvbox"), .theme("gruvbox"), "Hyprland's comma")
    t.equal(try? CommandParser.parse("theme Tokyo Night"), .theme("tokyo-night"),
            "a display name read across from an Omarchy config finds the same directory")
    // The one verb whose argument may be missing, because clearing the theme has to be sayable
    // and `theme none` would collide with a directory somebody could name.
    t.equal(try? CommandParser.parse("theme"), .theme(""), "and bare means your own colours back")
    t.equal(try? CommandParser.parse("bg city.jpg"), .background("city.jpg"), "a background by name")
    t.equal(try? CommandParser.parse("background City.JPG"), .background("City.JPG"),
            "not slugified — it is a file name, with an extension and a case of its own")
    t.expect((try? CommandParser.parse("background")) == nil, "which does have to be given")
    for spelling in ["nextbackground", "bgnext", "background-next"] {
        t.equal(try? CommandParser.parse(spelling), .nextBackground, "\(spelling) cycles")
    }
}

h.test("the background cycle is the one Omarchy walks") { t in
    let files = ["0-a.jpg", "1-b.png", "2-c.webp"]
    t.equal(Backgrounds.next(after: "0-a.jpg", in: files), "1-b.png", "one step on")
    t.equal(Backgrounds.next(after: "2-c.webp", in: files), "0-a.jpg", "and it wraps at the end")
    t.equal(Backgrounds.next(after: nil, in: files), "0-a.jpg", "nothing current starts at the first")
    t.equal(Backgrounds.next(after: "gone.jpg", in: files), "0-a.jpg",
            "and so does a name that is no longer there, rather than refusing to cycle")
    t.equal(Backgrounds.next(after: "only.jpg", in: ["only.jpg"]), "only.jpg", "one file cycles to itself")
    t.equal(Backgrounds.next(after: nil, in: []), nil, "and an empty folder has no next")
}

h.test("a backgrounds folder is filtered and sorted the same way twice") { t in
    let listed = Backgrounds.list([
        "2-b.PNG", ".DS_Store", "README.md", "0-a.jpg", "1-c.webp", "LICENSE", ".hidden.jpg",
    ])
    t.equal(listed, ["0-a.jpg", "1-c.webp", "2-b.PNG"],
            "pictures only, in codepoint order so two machines agree — and the extension's case "
            + "does not decide whether it is one")
    t.equal(Backgrounds.list(listed), listed, "and listing the list again changes nothing")
    // The order the menu draws and the order the key walks are the same list, by construction.
    t.equal(Backgrounds.next(after: listed.last, in: listed), listed.first,
            "so cycling and listing cannot drift apart")
}

// MARK: - The Style menu

h.test("Style is always at the root, because it is how you get a theme at all") { t in
    let m = MenuState(root: MenuModel.root(loginItem: .unavailable("needs /Applications"),
                                           config: Config()), visibleRows: 10)
    // Unlike Setup, which goes when both its rows are unavailable, Style stays even on a
    // machine with no themes and no network: it is the level you go to *to* get one, so leaving
    // it out exactly when it is most needed would be the wrong way round.
    t.equal(m.visible.map(\.title), ["Learn", "Style", "Setup", "Quit"], "still there with nothing behind it")
    t.equal(MenuModel.style(StyleMenu()).map(\.title), ["Theme"],
            "holding the theme list, and no Background row until there are pictures")
}

h.test("Background is left out when there are no images") { t in
    // The Setup-when-empty rule, one level down — and the usual case, since toe ships no
    // pictures of its own.
    t.equal(MenuModel.style(StyleMenu()).count, 1, "nothing to show, so no row leading to it")
    let withPictures = StyleMenu(current: "gruvbox", backgrounds: ["a.jpg", "b.jpg"])
    t.equal(MenuModel.style(withPictures).map(\.title), ["Theme", "Background"], "and it appears with them")
}

h.test("the theme you are on is marked, and so is having none") { t in
    let have = [ThemeRef(slug: "tokyo-night", name: "Tokyo Night"),
                ThemeRef(slug: "gruvbox", name: "Gruvbox")]
    let themed = MenuModel.themes(StyleMenu(themes: have, current: "gruvbox"))
    t.equal(themed.map(\.title), ["Tokyo Night", "Gruvbox", "Your own colours"],
            "what is installed, then the way back out")
    t.equal(themed.filter { $0.value == MenuModel.checkmark }.map(\.title), ["Gruvbox"],
            "exactly one is marked, with the tick Omarchy marks a current choice with")
    t.equal(themed.first?.action, .run(.theme("tokyo-night")), "and a row runs the theme command")

    let bare = MenuModel.themes(StyleMenu(themes: have))
    t.equal(bare.filter { $0.value == MenuModel.checkmark }.map(\.title), ["Your own colours"],
            "no theme is a state the list can show, not an absence of state")
    t.equal(bare.last?.action, .run(.theme("")), "and choosing it clears the name")
}

h.test("Style lists what is instant, Install what has to be fetched") { t in
    // Omarchy's split, and what it buys: nothing in Style › Theme can start a nine-megabyte
    // download, and Install stays a catalogue rather than a list that empties as you use it.
    let style = StyleMenu(
        themes: [ThemeRef(slug: "rose-pine", name: "Rose Pine")],
        available: [RemoteTheme(slug: "nord", name: "Nord",
                                backgrounds: [RemoteFile(name: "a.jpg", bytes: 4_300_000)]),
                    RemoteTheme(slug: "everforest", name: "Everforest", backgrounds: [])],
        current: "rose-pine")

    let mine = MenuModel.themes(style)
    t.equal(mine.map(\.title), ["Rose Pine", "Your own colours"],
            "what is on the disk, then the way back out — and nothing that would download")
    t.equal(mine.first?.value, MenuModel.checkmark, "the one you are on is marked")

    let catalogue = MenuModel.installableThemes(style)
    t.equal(catalogue.map(\.title), ["Nord", "Everforest"], "everything Omarchy publishes")
    // The size is the disclosure: these run from a third of a megabyte to nine, and a row that
    // fetched nine megabytes without saying so first would be a row that surprised you.
    t.equal(catalogue.first?.value, "4.1 MB", "and a download says what it costs")
    t.equal(catalogue.last?.value, "", "one with no pictures costs nothing worth printing")
    // One command either way: choosing a theme is the same act wherever the row lives.
    t.equal(catalogue.first?.action, .run(.theme("nord")),
            "and is chosen the same way as one you have")

    // Install is a row at the root only while there is something behind it.
    t.equal(MenuModel.install(StyleMenu()).isEmpty, true,
            "a machine that has never fetched the catalogue is offered no Install at all")
    guard case .submenu(let inner)? = MenuModel.install(style).first?.action else {
        return t.expect(false, "Install holds Omarchy's Style level")
    }
    t.equal(MenuModel.install(style).map(\.title), ["Style"], "Omarchy's own depth, kept")
    t.equal(inner.map(\.title), ["Theme"], "with Theme under it")
}

h.test("Remove lists the themes on the disk, and nothing when there are none") { t in
    let style = StyleMenu(themes: [ThemeRef(slug: "gruvbox", name: "Gruvbox"),
                                   ThemeRef(slug: "nord", name: "Nord")],
                          current: "gruvbox")
    guard case .submenu(let themes)? = MenuModel.remove(style).first?.action else {
        return t.expect(false, "Remove holds a Theme level")
    }
    t.equal(MenuModel.remove(style).map(\.title), ["Theme"], "one kind of thing to remove")
    t.equal(themes.map(\.title), ["Gruvbox", "Nord"], "every folder, fetched or hand-written")
    t.equal(themes.first?.action, .run(.removeTheme("gruvbox")),
            "including the one in effect, which hands your own colours back on the way out")
    t.equal(themes.compactMap(\.value).count, 0,
            "and no tick: in a list called Remove one would read as `already gone`")
    t.equal(MenuModel.remove(StyleMenu()).isEmpty, true, "nothing to remove, no row offering to")
}

h.test("an empty list says it is fetching rather than looking short") { t in
    let rows = MenuModel.installableThemes(StyleMenu(fetching: true))
    t.equal(rows.map(\.title), ["Fetching Omarchy's themes…"],
            "said, not left to be inferred from a list with nothing in it")
    t.equal(rows.first?.leadsOn, false, "it does not lead anywhere")
    var m = MenuState(root: rows, visibleRows: 10)
    t.equal(m.activate(), MenuOutcome.none, "and pressing it does nothing, leaving the menu up")
    t.equal(MenuModel.installableThemes(StyleMenu()).isEmpty, true,
            "and once it is not fetching, a bare list is bare enough to take Install with it")
    t.equal(MenuModel.themes(StyleMenu()).map(\.title), ["Your own colours"],
            "while Style always has the way back out")
}

h.test("the Background level is shaped like the Theme level above it") { t in
    let rows = MenuModel.backgrounds(StyleMenu(current: "gruvbox",
                                               backgrounds: ["city.jpg", "city.png"],
                                               currentBackground: "city.png"))
    t.equal(rows.map(\.title), ["city.jpg", "city.png", "Next background"],
            "the choices, then the action — as Your own colours comes after the themes")
    t.equal(rows.last?.action, .run(.nextBackground), "and that last row is the one that cycles")
    t.equal(rows.compactMap(\.icon).count, 0,
            "no icons: one icon among four rows indents that row's text past the rest")
    t.equal(MenuModel.themes(StyleMenu()).compactMap(\.icon).count, 0, "as the theme list has none")
    t.equal(rows.first { $0.title == "city.png" }?.value, MenuModel.checkmark,
            "with the one on screen marked")
    t.equal(rows.first?.value, nil, "and only that one")
    t.expect(rows.first?.title.hasSuffix(".jpg") == true,
             "the extension stays, or two files would give two rows saying the same word")
}

h.test("a theme can be found by typing its name from the root") { t in
    let style = StyleMenu(themes: [ThemeRef(slug: "gruvbox", name: "Gruvbox")])
    var m = MenuState(root: MenuModel.root(loginItem: .off, config: Config(), style: style),
                      visibleRows: 10)
    m.type("gruv")
    // Twice, because a theme on the disk is two rows now: the one that wears it and the one that
    // deletes it. That is upstream's answer too — searching Omarchy's menu for a theme finds its
    // Install row beside its Remove row — and the path under each is what tells them apart.
    t.equal(m.visible.map(\.title), ["Gruvbox", "Gruvbox"], "two levels down, without going there")
    t.equal(m.visible.map(\.subtitle), ["Style › Theme", "Remove › Theme"],
            "and each says where it was found")
    t.equal(m.activate(), .run(.theme("gruvbox")), "the first is the one that wears it")

    var picture = MenuState(root: MenuModel.root(loginItem: .off, config: Config(),
                                                 style: StyleMenu(current: "gruvbox",
                                                                  backgrounds: ["city.jpg"])),
                            visibleRows: 10)
    picture.type("city")
    t.equal(picture.activate(), .run(.background("city.jpg")), "a picture is reachable the same way")
}

// MARK: - Following Omarchy's tree

h.test("the root is Omarchy's root, with what a Mac cannot do left out") { t in
    // Upstream's order is Apps, Learn, Trigger, Style, Setup, Install, Remove, Update, About,
    // System. Every row toe has an analogue for, in that order, and Quit — which has no
    // counterpart, Omarchy's System being a power menu for the machine — last. Trigger is not
    // among them: the eight rows upstream hangs off it are Linux tools bar one, and that one
    // switch is a Setup row here rather than two levels of scaffolding holding it up.
    let full = StyleMenu(themes: [ThemeRef(slug: "gruvbox", name: "Gruvbox")],
                         available: [RemoteTheme(slug: "nord", name: "Nord", backgrounds: [])],
                         current: "gruvbox", backgrounds: ["a.jpg"])
    let c = try Config.parse(Config.defaultTOML)
    let rows = MenuModel.root(loginItem: .off, config: c, style: full, version: "0.9.7")
    t.equal(rows.map(\.title),
            ["Learn", "Style", "Setup", "Install", "Remove", "About", "Quit"],
            "the same names at the same depth, in the same order")
    t.equal(rows.first { $0.title == "About" }?.value, "0.9.7",
            "About is the one fact toe can report about itself, in the second column")
    t.equal(rows.first { $0.title == "About" }?.action, .note, "and nothing to press")
    t.expect(MenuModel.root(loginItem: .off, config: c, style: full)
                .allSatisfy { $0.title != "About" },
             "a build with no stamped version leaves the row out rather than saying `unknown`")
}

h.test("Learn is the keybindings and the three manuals that are about this machine") { t in
    let rows = MenuModel.learn()
    t.equal(rows.map(\.title), ["Keybindings", "toe", "Omarchy", "Hyprland"],
            "toe stands where learn.omarchy does — the system's own manual")
    t.equal(rows.first?.action, .page(.keybindings), "the first row is still the page")
    t.expect(rows.dropFirst().allSatisfy {
        if case .run(.exec(let line)) = $0.action { return line.hasPrefix("open https://") }
        return false
    }, "and the rest open a URL, which is all upstream's links do")
}

h.test("a binding can open the menu at a level, the way omarchy-menu toggle does") { t in
    let style = StyleMenu(themes: [ThemeRef(slug: "gruvbox", name: "Gruvbox")],
                          current: "gruvbox", backgrounds: ["city.jpg", "coast.jpg"])
    let root = MenuModel.root(loginItem: .off, config: Config(), style: style)

    var m = MenuState(root: root, visibleRows: 10, path: MenuRoute.background.path)
    t.equal(m.breadcrumb, ["Style", "Background"], "opened three rows in")
    t.equal(m.prompt, "Background…", "and the placeholder says so")
    t.equal(m.visible.map(\.title), ["city.jpg", "coast.jpg", "Next background"], "at the pictures")
    t.equal(m.pop(), .popped, "Escape still climbs out of it")
    t.equal(m.breadcrumb, ["Style"], "one rung at a time, into the tree it was opened inside")

    // A route that does not resolve stops where it can rather than failing: Background exists
    // only while the current theme has pictures, and the key is bound whether it does or not.
    let bare = MenuState(root: MenuModel.root(loginItem: .off, config: Config(), style: StyleMenu()),
                         visibleRows: 10, path: MenuRoute.background.path)
    t.equal(bare.breadcrumb, ["Style"], "as deep as the tree goes, and no error")
    t.equal(MenuState(root: root, visibleRows: 10).breadcrumb, [],
            "and no path at all is the root, which is every other way the menu opens")
}

h.test("a disabled row is listed, ticked, and cannot be reached") { t in
    // Omarchy's `disabled`: the cursor steps over it, the pointer does not take it, Return does
    // nothing to it, and a search does not turn it up.
    let style = StyleMenu(themes: [ThemeRef(slug: "gruvbox", name: "Gruvbox")],
                          available: [RemoteTheme(slug: "gruvbox", name: "Gruvbox", backgrounds: []),
                                      RemoteTheme(slug: "nord", name: "Nord", backgrounds: [])])
    var m = MenuState(root: MenuModel.installableThemes(style), visibleRows: 10)
    t.equal(m.visible.map(\.title), ["Gruvbox", "Nord"], "both rows are listed")
    t.equal(m.selection, 1, "but the cursor opens on the first one it could act on")
    m.move(by: -1)
    t.equal(m.selection, 1, "and moving up cannot land on the one above it")
    m.select(row: 0)
    t.equal(m.selection, 1, "a click does not take it either")
    m.moveToTop()
    t.equal(m.selection, 1, "nor does Home")

    m.type("gruv")
    t.equal(m.visible.count, 0, "and a search that would find it does not offer it")
    m.backspace(); m.backspace(); m.backspace(); m.backspace()
    t.equal(m.visible.count, 2, "the level comes back whole")

    // The one way the cursor can end up on one: it was selectable when you arrived, and a
    // download finishing turned it into an installed row under your hand.
    var landed = MenuState(root: [MenuItem(title: "Gruvbox", isDisabled: true,
                                           action: .run(.theme("gruvbox")))],
                           visibleRows: 10)
    t.equal(landed.activate(), MenuOutcome.none, "pressing it does nothing, leaving the menu up")
}

exit(h.report())
