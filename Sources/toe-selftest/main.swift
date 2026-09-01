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

exit(h.report())
