import Foundation

/// Per-edge gap values, applied only when a node box is handed to a window.
public struct Gaps: Equatable, Sendable {
    public var inner: Double
    public var outer: Double
    public init(inner: Double = 5, outer: Double = 10) {
        self.inner = inner
        self.outer = outer
    }
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

        // Resolve what we are splitting. Fall back to any leaf, as Hyprland's fail-safe does.
        var openingOn: DwindleNode?
        if let anchor, let anchorNode = nodes[anchor], anchorNode !== node {
            openingOn = anchorNode
        } else if let focalPoint, let hit = self.node(at: focalPoint), hit !== node {
            openingOn = hit
        } else {
            openingOn = root?.leaves().first { $0 !== node }
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
            // Hyprland consults the pointer here. macOS has no cursor-follows-focus, so a
            // focal point is only present for `movewindow`; otherwise behave as force_split = 2.
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
    /// the tree shape is untouched. This is the behaviour AeroSpace cannot reproduce.
    public func swap(_ a: WindowID, _ b: WindowID) {
        guard a != b, let na = nodes[a], let nb = nodes[b] else { return }
        na.window = b
        nb.window = a
        nodes[a] = nb
        nodes[b] = na
        recalculate()
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
}
