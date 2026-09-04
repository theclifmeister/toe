import Foundation

/// Per-edge gap values, applied only when a node box is handed to a window.
public struct Gaps: Equatable, Sendable {
    public var inner: Double
    public var outer: Double
    public init(inner: Double = 8, outer: Double = 15) {
        self.inner = inner
        self.outer = outer
    }
}

/// Which edges of a window are being pulled. Empty is Hyprland's `CORNER_NONE`: the keyboard
/// case, where the nearest split of each orientation is the one that moves.
public struct ResizeEdges: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let left   = ResizeEdges(rawValue: 1 << 0)
    public static let right  = ResizeEdges(rawValue: 1 << 1)
    public static let top    = ResizeEdges(rawValue: 1 << 2)
    public static let bottom = ResizeEdges(rawValue: 1 << 3)
}

/// One dwindle tree. There is exactly one of these per workspace.
///
/// Direct port of `CHyprDwindleLayout` restricted to a single workspace, since on macOS
/// each workspace's windows are managed independently.
public final class DwindleLayout {

    /// The monitor's usable area (menu bar and Dock already excluded), pre-gap.
    /// Hyprland's monitor box minus reserved area.
    public var area: Box
    public var options: DwindleOptions

    public private(set) var root: DwindleNode?
    private var nodes: [WindowID: DwindleNode] = [:]
    /// Creation order, so the insertion fail-safe can pick the oldest window the way
    /// Hyprland's `getFirstNodeOnWorkspace` scans `m_dwindleNodesData` in list order.
    private var order: [WindowID] = []

    public init(area: Box, options: DwindleOptions = DwindleOptions()) {
        self.area = area
        self.options = options
    }

    public var windowIDs: [WindowID] { root?.leaves().compactMap(\.window) ?? [] }
    public var isEmpty: Bool { nodes.isEmpty }
    public func contains(_ id: WindowID) -> Bool { nodes[id] != nil }
    public func node(for id: WindowID) -> DwindleNode? { nodes[id] }

    /// The un-gapped node box for a window — Hyprland's
    /// `getWindowIdealBoundingBoxIgnoreReserved`, which is what directional focus uses.
    public func idealBox(of id: WindowID) -> Box? { nodes[id]?.box }

    /// The leaf whose box contains `point`.
    public func node(at point: Point) -> DwindleNode? {
        root?.leaves().first { $0.box.contains(point) }
    }

    /// Port of `getClosestNodeOnWorkspace`: the leaf nearest `point`, used when the pointer
    /// is on the monitor but outside the tiling area (Hyprland's reserved strip).
    public func closestNode(to point: Point) -> DwindleNode? {
        root?.leaves().min { $0.box.distanceSquared(to: point) < $1.box.distanceSquared(to: point) }
    }

    // MARK: - Insertion

    /// Port of `onWindowCreatedTiling`.
    ///
    /// - Parameters:
    ///   - anchor: the node to split. Hyprland with `use_active_for_splits = true` (its
    ///     default, which Omarchy keeps) uses the focused window; callers pass that here.
    ///   - focalPoint: only consulted when `force_split == 0`, or when re-inserting a window
    ///     that is being moved (`isFirstMap == false`) — see `DwindleLayout.cpp:382`.
    ///   - isFirstMap: false when this is a re-insertion driven by `movewindow`.
    @discardableResult
    public func insert(
        _ id: WindowID,
        anchor: WindowID?,
        focalPoint: Point? = nil,
        isFirstMap: Bool = true
    ) -> DwindleNode {
        if let existing = nodes[id] { return existing }

        let node = DwindleNode(window: id)
        nodes[id] = node
        order.append(id)

        // Resolve what we are splitting, in Hyprland's order: the focused window, else the
        // leaf under the pointer, else — when the pointer is off the tiling area, its
        // `isPointOnReservedArea` case — the closest leaf, else the fail-safe oldest leaf.
        var openingOn: DwindleNode?
        if let anchor, let anchorNode = nodes[anchor], anchorNode !== node {
            openingOn = anchorNode
        } else if let focalPoint, let hit = self.node(at: focalPoint), hit !== node {
            openingOn = hit
        } else if let focalPoint, !area.contains(focalPoint),
                  let near = closestNode(to: focalPoint), near !== node {
            openingOn = near
        } else {
            openingOn = order.first { $0 != id }.flatMap { nodes[$0] }
        }

        // First window on the workspace: it takes the whole usable area.
        guard let target = openingOn else {
            node.box = area
            root = node
            return node
        }

        let newParent = DwindleNode()
        newParent.box = target.box
        newParent.parent = target.parent
        newParent.splitRatio = clampf(options.defaultSplitRatio, 0.1, 1.9)

        let sideBySide = newParent.box.w > newParent.box.h * options.splitWidthMultiplier
        newParent.splitTop = !sideBySide

        // Child ordering.
        if options.forceSplit == 0 || !isFirstMap {
            // Hyprland consults the pointer here, and so do we: the focal point is the
            // cursor on a fresh map, or the edge probe `movewindow` computes. With no point
            // at all — a headless insert — behave as force_split = 2.
            let firstHalf: Bool
            if let fp = focalPoint {
                firstHalf = sideBySide
                    ? fp.x < newParent.box.x + newParent.box.w / 2.0
                    : fp.y < newParent.box.y + newParent.box.h / 2.0
            } else {
                firstHalf = false
            }
            newParent.children = firstHalf ? [node, target] : [target, node]
        } else if options.forceSplit == 1 {
            newParent.children = [node, target]
        } else {
            newParent.children = [target, node]
        }

        // split_bias: hand the larger half to a specific window.
        let first = newParent.children[0]
        if (options.splitBias == 1 && first === node) || (options.splitBias == 2 && first === target) {
            newParent.splitRatio = 2.0 - newParent.splitRatio
        }

        // Re-link the tree.
        if let grandParent = target.parent, grandParent.children.count == 2 {
            if grandParent.children[0] === target {
                grandParent.children[0] = newParent
            } else {
                grandParent.children[1] = newParent
            }
        } else {
            root = newParent
        }

        target.parent = newParent
        node.parent = newParent

        newParent.recalcSizePosRecursive(options)
        return node
    }

    // MARK: - Removal

    /// Port of `onWindowRemovedTiling`: the sibling absorbs the parent's box and slot.
    public func remove(_ id: WindowID) {
        guard let node = nodes.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }

        guard let parent = node.parent else {
            // Last window on the workspace.
            root = nil
            return
        }

        guard let sibling = node.sibling else {
            root = nil
            return
        }

        sibling.box = parent.box
        sibling.parent = parent.parent

        if let grandParent = parent.parent, grandParent.children.count == 2 {
            if grandParent.children[0] === parent {
                grandParent.children[0] = sibling
            } else {
                grandParent.children[1] = sibling
            }
        } else {
            root = sibling
        }

        parent.children = []
        node.parent = nil

        if let p = sibling.parent {
            p.recalcSizePosRecursive(options)
        } else {
            sibling.recalcSizePosRecursive(options)
        }
    }

    // MARK: - Rearranging

    /// Port of `switchWindows` — Omarchy's `swapwindow`. Only the window payloads move;
    /// the tree shape is untouched, so a swap never reshuffles the rest of the layout.
    public func swap(_ a: WindowID, _ b: WindowID) {
        guard a != b, let na = nodes[a], let nb = nodes[b] else { return }
        na.window = b
        nb.window = a
        nodes[a] = nb
        nodes[b] = na
        swapOrder(a, b)
        recalculate()
    }

    /// `switchWindows` across two trees. Hyprland swaps the node payloads and then the
    /// windows' monitor/workspace pointers — it never re-inserts, so both shapes survive.
    public static func swap(_ a: WindowID, in la: DwindleLayout, with b: WindowID, in lb: DwindleLayout) {
        guard a != b else { return }
        if la === lb {
            la.swap(a, b)
            return
        }
        guard let na = la.nodes[a], let nb = lb.nodes[b] else { return }

        na.window = b
        nb.window = a

        la.nodes[a] = nil
        la.nodes[b] = na
        lb.nodes[b] = nil
        lb.nodes[a] = nb

        // The nodes keep their creation order; only the window each one carries moves.
        if let ia = la.order.firstIndex(of: a) { la.order[ia] = b }
        if let ib = lb.order.firstIndex(of: b) { lb.order[ib] = a }

        la.recalculate()
        lb.recalculate()
    }

    private func swapOrder(_ a: WindowID, _ b: WindowID) {
        guard let ia = order.firstIndex(of: a), let ib = order.firstIndex(of: b) else { return }
        order.swapAt(ia, ib)
    }

    /// Port of `moveWindowTo` — the `movewindow` dispatcher. Removes the window and
    /// re-inserts it at a focal point just past the given edge of its current box.
    public func moveWindow(_ id: WindowID, _ dir: Direction) {
        guard let node = nodes[id] else { return }
        let b = node.box
        let focal: Point
        switch dir {
        case .up:    focal = Point(x: b.x + b.w / 2.0, y: b.y - 1.0)
        case .down:  focal = Point(x: b.x + b.w / 2.0, y: b.y + b.h + 1.0)
        case .left:  focal = Point(x: b.x - 1.0, y: b.y + b.h / 2.0)
        case .right: focal = Point(x: b.x + b.w + 1.0, y: b.y + b.h / 2.0)
        }
        remove(id)
        insert(id, anchor: nil, focalPoint: focal, isFirstMap: false)
    }

    /// Port of `toggleSplit`: flip the orientation of the focused window's parent split.
    public func toggleSplit(_ id: WindowID) {
        guard let parent = nodes[id]?.parent, parent.box.w != 0, parent.box.h != 0 else { return }
        parent.splitTop.toggle()
        parent.recalcSizePosRecursive(options)
    }

    /// Port of `swapSplit`: exchange the two children of the focused window's parent.
    public func swapSplit(_ id: WindowID) {
        guard let parent = nodes[id]?.parent, parent.children.count == 2 else { return }
        parent.children.swapAt(0, 1)
        parent.recalcSizePosRecursive(options)
    }

    /// Port of `alterSplitRatio`.
    public func alterSplitRatio(_ id: WindowID, by delta: Double, exact: Bool = false) {
        guard let parent = nodes[id]?.parent else { return }
        let newRatio = exact ? delta : parent.splitRatio + delta
        parent.splitRatio = clampf(newRatio, 0.1, 1.9)
        parent.recalcSizePosRecursive(options)
    }

    /// Port of `resizeActiveWindow` — `resizeactive`, and the tiled half of a mouse resize.
    ///
    /// `dx` and `dy` are how far an edge moves, in points, positive right and down. That is the
    /// pointer delta Hyprland feeds this from `IHyprLayout::onMouseMove`, and it is *not* the
    /// change in the window's size: pulling a left edge leftwards is a negative `dx`, and the
    /// `LEFT` branch below turns it into the left-hand neighbour giving up that much. With no
    /// edges — the keyboard — the split moves by the amount, whichever side of it this window is
    /// on, so `resizeactive 100 0` grows a left-hand window and shrinks a right-hand one. That
    /// is Omarchy's binding and it is kept as it is.
    ///
    /// Hyprland ships `dwindle:smart_resizing = 1` and Omarchy leaves it, so this is that branch
    /// and only that branch. The walk up the tree finds, per orientation, the *outer* split —
    /// the first ancestor where this window's subtree sits on the near side of the edge being
    /// pulled, so that moving the split moves the edge — and, on the way to it, an *inner*
    /// split of the same orientation, whose ratio is then re-solved so the window's opposite
    /// edge stays where it was. Without that correction the whole subtree would stretch in
    /// proportion and the edge the user is not holding would drift, which is the difference
    /// between a drag and a zoom. With no edges the first ancestor of each orientation is the
    /// outer one and there is no inner.
    ///
    /// Measured on the un-gapped node boxes, the way Hyprland measures against the monitor's
    /// reserved area: a gap is a constant inset, so an edge's displacement is the same number in
    /// either space, and the node box is the one whose width the ratio is a fraction of.
    ///
    /// Returns false when nothing could move — the only window on the workspace, or a
    /// side-by-side pair asked for the vertical axis — so the caller can skip the render.
    @discardableResult
    public func resizeActive(_ id: WindowID, dx: Double, dy: Double, edges: ResizeEdges) -> Bool {
        guard let node = nodes[id] else { return false }

        // An edge that is the display's edge cannot move, so pulling it pulls the other one —
        // Hyprland's DISPLAYLEFT and friends, which is also why a `Super`+right-drag on a
        // leftmost window resizes it from the right. A window spanning the full width has no
        // horizontal freedom at all, and that axis is dropped rather than left to move a split.
        let displayLeft   = STICKS(node.box.minX, area.minX)
        let displayRight  = STICKS(node.box.maxX, area.maxX)
        let displayTop    = STICKS(node.box.minY, area.minY)
        let displayBottom = STICKS(node.box.maxY, area.maxY)

        let dx = displayLeft && displayRight ? 0 : dx
        let dy = displayTop && displayBottom ? 0 : dy

        let none   = edges.isEmpty
        let left   = edges.contains(.left)   || displayRight
        let top    = edges.contains(.top)    || displayBottom
        let right  = edges.contains(.right)  || displayLeft
        let bottom = edges.contains(.bottom) || displayTop

        // PVOUTER / PVINNER / PHOUTER / PHINNER. Each is the *child* on the path, not the split
        // itself, because which child it is decides how the inner ratio is re-solved.
        var vOuter: DwindleNode?, vInner: DwindleNode?
        var hOuter: DwindleNode?, hInner: DwindleNode?

        var current = node
        while let parent = current.parent {
            let first = parent.children.first === current
            if vOuter == nil, parent.splitTop, none || (top && !first) || (bottom && first) {
                vOuter = current
            } else if vOuter == nil, vInner == nil, parent.splitTop {
                vInner = current
            } else if hOuter == nil, !parent.splitTop, none || (left && !first) || (right && first) {
                hOuter = current
            } else if hOuter == nil, hInner == nil, !parent.splitTop {
                hInner = current
            }
            if vOuter != nil && hOuter != nil { break }
            current = parent
        }

        var moved = false

        if dx != 0, let outer = hOuter, let split = outer.parent, split.box.w > 0 {
            split.splitRatio = clampf(split.splitRatio + dx * 2.0 / split.box.w, 0.1, 1.9)
            if let inner = hInner, let innerSplit = inner.parent, innerSplit.box.w > 0 {
                // Re-solve the inner split from what the inner child measured *before* the
                // outer one moved: that width plus (or minus) the pull is the width that keeps
                // the far edge still, and the ratio is that width as a fraction of the half.
                let original = inner.box.w
                split.recalcSizePosRecursive(options)
                if innerSplit.children.first === inner {
                    innerSplit.splitRatio = clampf((original - dx) / innerSplit.box.w * 2.0, 0.1, 1.9)
                } else {
                    innerSplit.splitRatio = clampf(2.0 - (original + dx) / innerSplit.box.w * 2.0, 0.1, 1.9)
                }
                innerSplit.recalcSizePosRecursive(options)
            } else {
                split.recalcSizePosRecursive(options)
            }
            moved = true
        }

        if dy != 0, let outer = vOuter, let split = outer.parent, split.box.h > 0 {
            split.splitRatio = clampf(split.splitRatio + dy * 2.0 / split.box.h, 0.1, 1.9)
            if let inner = vInner, let innerSplit = inner.parent, innerSplit.box.h > 0 {
                let original = inner.box.h
                split.recalcSizePosRecursive(options)
                if innerSplit.children.first === inner {
                    innerSplit.splitRatio = clampf((original - dy) / innerSplit.box.h * 2.0, 0.1, 1.9)
                } else {
                    innerSplit.splitRatio = clampf(2.0 - (original + dy) / innerSplit.box.h * 2.0, 0.1, 1.9)
                }
                innerSplit.recalcSizePosRecursive(options)
            } else {
                split.recalcSizePosRecursive(options)
            }
            moved = true
        }

        return moved
    }

    /// `growactive`: `dx` and `dy` are how much *this window* grows, whichever side of its
    /// splits it is on. Not a Hyprland dispatcher — `resizeactive` moves the split, and from the
    /// right-hand window the key labelled `=` therefore shrinks the window you are in, which is
    /// the surprise this exists to remove. It is `resizeActive` with the sign settled here: a
    /// window on the first side of a split (left, top) grows when the split moves away from it
    /// in the positive direction, a window on the second side grows when it moves the other
    /// way. The split found is the same one `resizeActive` finds with no edges — the nearest
    /// ancestor of that orientation — so the two verbs never disagree about *which* split.
    @discardableResult
    public func growActive(_ id: WindowID, dx: Double, dy: Double) -> Bool {
        guard let node = nodes[id] else { return false }
        // Which child of the nearest split of an orientation this window's subtree is. Nil when
        // there is none — that axis then has nothing to move, and `resizeActive` says so.
        func onFirstSide(ofSplitTop splitTop: Bool) -> Bool? {
            var current = node
            while let parent = current.parent {
                if parent.splitTop == splitTop { return parent.children.first === current }
                current = parent
            }
            return nil
        }
        let h = onFirstSide(ofSplitTop: false)
        let v = onFirstSide(ofSplitTop: true)
        return resizeActive(id, dx: h == false ? -dx : dx, dy: v == false ? -dy : dy, edges: [])
    }

    // MARK: - Output

    /// Re-run the whole tree against the current `area`. Called on config reload and on
    /// display reconfiguration.
    public func recalculate() {
        guard let root else { return }
        root.box = area
        root.recalcSizePosRecursive(options)
    }

    /// The frames to actually write to windows: node boxes with gaps applied.
    ///
    /// Port of `applyNodeDataToWindow`'s gap handling — an edge that sticks to the monitor's
    /// usable area gets the outer gap, every interior edge gets the inner gap.
    public func frames(gaps: Gaps) -> [WindowID: Box] {
        guard let root else { return [:] }
        var out: [WindowID: Box] = [:]
        for leaf in root.leaves() {
            guard let id = leaf.window else { continue }
            let b = leaf.box
            let left   = STICKS(b.minX, area.minX) ? gaps.outer : gaps.inner
            let right  = STICKS(b.maxX, area.maxX) ? gaps.outer : gaps.inner
            let top    = STICKS(b.minY, area.minY) ? gaps.outer : gaps.inner
            let bottom = STICKS(b.maxY, area.maxY) ? gaps.outer : gaps.inner
            out[id] = b.inset(top: top, left: left, bottom: bottom, right: right).rounded()
        }
        return out
    }

    /// Every leaf as (window, un-gapped node box) — the input to directional search.
    public func idealBoxes() -> [(id: WindowID, box: Box)] {
        guard let root else { return [] }
        return root.leaves().compactMap { leaf in
            leaf.window.map { (id: $0, box: leaf.box) }
        }
    }

    // MARK: - Session

    /// The tree, for `SessionSnapshot`. Boxes are left out: `restore` derives them.
    public func snapshot() -> LayoutSnapshot {
        LayoutSnapshot(root: root.map(NodeSnapshot.init), order: order)
    }

    /// Rebuild the tree from a snapshot, discarding whatever this layout held.
    ///
    /// The file is decoded before it is trusted, so this is written to survive a damaged one:
    /// a leaf that repeats a window already placed is dropped, a split that has lost one side
    /// collapses into the side it kept — exactly what `remove` would have done had the window
    /// gone while toe was running — and a split that has lost both disappears with it. Nothing
    /// here can produce a tree that `recalculate` will not walk.
    public func restore(_ snapshot: LayoutSnapshot) {
        nodes.removeAll()
        order.removeAll()
        root = snapshot.root.flatMap { rebuild($0, depth: 0) }
        root?.parent = nil

        // Keep the recorded creation order, minus anything that did not make it into the
        // tree, plus anything the order forgot — `order` is what the insertion fail-safe
        // reads, so every live window has to be in it.
        let placed = Set(nodes.keys)
        order = snapshot.order.filter { placed.contains($0) }
        let known = Set(order)
        for id in windowIDs where !known.contains(id) { order.append(id) }

        recalculate()
    }

    private func rebuild(_ snapshot: NodeSnapshot, depth: Int) -> DwindleNode? {
        guard depth < NodeSnapshot.maxDepth else { return nil }

        if let window = snapshot.window {
            guard nodes[window] == nil else { return nil }
            let leaf = DwindleNode(window: window)
            nodes[window] = leaf
            return leaf
        }

        // `prefix(2)` rather than a count check: a third child is never built, so it can
        // never end up registered in `nodes` with nothing pointing at it.
        let children = snapshot.children.prefix(2).compactMap { rebuild($0, depth: depth + 1) }
        guard children.count == 2 else { return children.first }

        let node = DwindleNode()
        node.splitTop = snapshot.splitTop
        node.splitRatio = clampf(snapshot.splitRatio, 0.1, 1.9)
        node.children = children
        children[0].parent = node
        children[1].parent = node
        return node
    }
}
