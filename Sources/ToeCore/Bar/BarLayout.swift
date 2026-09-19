import Foundation

/// Where each item sits along the bar, and what a click at an x lands on.
///
/// This is `Bar.qml`'s `horizontalBar` as arithmetic: a left row inset `space(8)` from the
/// screen edge, a right row inset the same from the other edge, and a centre section built
/// around one *anchor* widget whose slot is centred on the bar's midpoint — the items before
/// it end where it begins and the items after it start where it ends, so the clock stays put
/// while its neighbours come and go. Without an anchor the centre section is centred as a
/// group, which is upstream's other arrangement.
///
/// Pure, so the selftest can lay a bar out with a measurer that returns a number per character
/// and check every x by hand. The real measurer is an `NSAttributedString` in `BarView`.
public enum BarLayout {

    /// One item and its slot: `x` to `x + width`, the bar's full height.
    public struct Placed: Equatable, Sendable {
        public let item: BarItem
        public let x: Double
        public let width: Double
        /// What the label measured, so the view can centre it in the slot without measuring
        /// twice.
        public let labelWidth: Double

        public var maxX: Double { x + width }
        public var midX: Double { x + width / 2 }
    }

    /// The label's width in points, at the size `BarMetrics.pointSize` gives its font role.
    public typealias Measure = (_ text: String, _ pointSize: Double) -> Double

    /// Lays `items` out across a bar `width` wide.
    ///
    /// `centre` is where the anchor's slot is centred: the bar's midpoint unless the caller
    /// says otherwise, which the notched display does — its centre section centres on the gap
    /// beside the notch rather than under it. `anchor` names the widget the centre section is
    /// built around; nil, or an anchor that is not among the items, centres the section as a
    /// whole.
    ///
    /// A concealed item — `isHidden` — is placed at zero width and its `gapAfter` dropped, which
    /// is what upstream's clipped indicator area does: the inactive indicators take no room
    /// until the centre is hovered, and the clock does not move when they appear because the
    /// anchor is what everything else is measured from.
    public static func place(_ items: [BarItem], width: Double, metrics: BarMetrics,
                             centre: Double? = nil, anchor: BarItem.Kind? = .clock,
                             measure: Measure) -> [Placed] {
        func measured(_ item: BarItem) -> (label: Double, slot: Double) {
            guard !item.isHidden else { return (0, 0) }
            let label = measure(item.text, metrics.pointSize(item.font))
            return (label, metrics.slotWidth(item.slot, labelWidth: label))
        }

        /// A run of items laid end to end from `x`, each followed by its gap.
        func row(_ run: [BarItem], from x: Double) -> [Placed] {
            var cursor = x
            return run.map { item in
                let (label, slot) = measured(item)
                let placed = Placed(item: item, x: cursor, width: slot, labelWidth: label)
                cursor += slot + (item.isHidden ? 0 : item.gapAfter)
                return placed
            }
        }

        /// How much room a run takes, gaps included — the last item's trailing gap too, which
        /// is inside the widget upstream (the workspace strip's `trailingGap` is part of its
        /// `implicitWidth`) and so part of where the next row starts.
        func extent(_ run: [BarItem]) -> Double {
            run.reduce(0) { total, item in
                let (_, slot) = measured(item)
                return total + slot + (item.isHidden ? 0 : item.gapAfter)
            }
        }

        let left = items.filter { $0.section == .left }
        let center = items.filter { $0.section == .center }
        let right = items.filter { $0.section == .right }
        let mid = centre ?? width / 2

        var placed = row(left, from: metrics.edgeMargin)
        placed += row(right, from: width - metrics.edgeMargin - extent(right))

        if let anchor, let at = center.firstIndex(where: { $0.kind == anchor }) {
            let before = Array(center[..<at]), after = Array(center[(at + 1)...])
            let (_, anchorSlot) = measured(center[at])
            let anchorX = mid - anchorSlot / 2
            placed += row(before, from: anchorX - extent(before))
            placed += row([center[at]], from: anchorX)
            // The anchor's own gap is honoured like anyone else's, though no anchor has one.
            placed += row(after, from: anchorX + anchorSlot + center[at].gapAfter)
        } else {
            placed += row(center, from: mid - extent(center) / 2)
        }
        return placed
    }

    /// The item under `x`, or nil over bare bar. Slots abut, so the first one whose span holds
    /// the point is the answer; a concealed item has no span and is never hit.
    public static func hit(x: Double, in placed: [Placed]) -> Placed? {
        placed.first { $0.width > 0 && x >= $0.x && x < $0.maxX }
    }
}
