import Foundation

/// Port of Hyprland's `SDwindleNodeData` (src/layout/DwindleLayout.cpp).
///
/// A binary tree. Leaves hold a window; internal nodes hold a split. `splitTop == true`
/// means the node is split into a top and a bottom child; `false` means left and right.
public final class DwindleNode {
    public var box: Box = Box(x: 0, y: 0, w: 0, h: 0)
    public weak var parent: DwindleNode?
    public var children: [DwindleNode] = []

    /// Frozen at insertion when `preserve_split` is on (Omarchy's setting).
    public var splitTop: Bool = false
    /// 1.0 == even split. Hyprland clamps to 0.1...1.9.
    public var splitRatio: Double = 1.0

    /// nil for internal nodes.
    public var window: WindowID?

    public init(window: WindowID? = nil) {
        self.window = window
    }

    public var isLeaf: Bool { children.isEmpty }

    /// The sibling under the same parent, if any.
    public var sibling: DwindleNode? {
        guard let p = parent, p.children.count == 2 else { return nil }
        return p.children[0] === self ? p.children[1] : p.children[0]
    }

    /// Depth-first collection of every leaf below (and including) this node.
    public func leaves() -> [DwindleNode] {
        if isLeaf { return window != nil ? [self] : [] }
        return children.flatMap { $0.leaves() }
    }

    /// Port of `SDwindleNodeData::recalcSizePosRecursive`.
    ///
    /// With `preserve_split` on, the orientation chosen at insertion is never revisited —
    /// that is what makes Hyprland's dwindle stable as windows come and go, and it is the
    /// behaviour i3-style container normalization destroys.
    public func recalcSizePosRecursive(
        _ opts: DwindleOptions,
        horizontalOverride: Bool = false,
        verticalOverride: Bool = false
    ) {
        guard children.count == 2 else { return }

        if !opts.preserveSplit && !opts.smartSplit {
            splitTop = box.h * opts.splitWidthMultiplier > box.w
        }

        if verticalOverride {
            splitTop = true
        } else if horizontalOverride {
            splitTop = false
        }

        let splitSide = !splitTop

        if splitSide {
            // split left/right
            let firstSize = box.w / 2.0 * splitRatio
            children[0].box = Box(x: box.x, y: box.y, w: firstSize, h: box.h).noNegativeSize()
            children[1].box = Box(x: box.x + firstSize, y: box.y, w: box.w - firstSize, h: box.h).noNegativeSize()
        } else {
            // split top/bottom
            let firstSize = box.h / 2.0 * splitRatio
            children[0].box = Box(x: box.x, y: box.y, w: box.w, h: firstSize).noNegativeSize()
            children[1].box = Box(x: box.x, y: box.y + firstSize, w: box.w, h: box.h - firstSize).noNegativeSize()
        }

        children[0].recalcSizePosRecursive(opts)
        children[1].recalcSizePosRecursive(opts)
    }
}

/// The `dwindle { ... }` section. Defaults are Hyprland's; Omarchy overrides
/// `preserve_split = true` and `force_split = 2`, which are the defaults we ship.
public struct DwindleOptions: Equatable, Sendable {
    /// Freeze split orientation at insertion time.
    public var preserveSplit: Bool = true
    /// 0 = follow focal point, 1 = new window always first (left/top), 2 = always second (right/bottom).
    public var forceSplit: Int = 2
    /// Not implemented as a layout mode; kept so config round-trips and recalc matches Hyprland.
    public var smartSplit: Bool = false
    /// `SIDEBYSIDE = box.w > box.h * splitWidthMultiplier`
    public var splitWidthMultiplier: Double = 1.0
    /// Clamped to 0.1...1.9 on use.
    public var defaultSplitRatio: Double = 1.0
    /// 0 = none, 1 = favour the new window, 2 = favour the existing one.
    public var splitBias: Int = 0

    public init() {}
}
