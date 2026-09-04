import Foundation

/// The decision behind a sideways dock swipe, kept apart from the event tap for the reason
/// `BorderGeometry` is kept apart from the border panel: this is the part the selftest can reach.
/// `DockSwipeTap` reads three integers off a `CGEvent` it has already identified as a dock swipe
/// and hands them here; this answers whether that event is the moment the gesture committed to a
/// horizontal direction — once per gesture, and never for a vertical one.
///
/// A dock swipe is continuous: `began`, then a run of `changed`, then `ended` or `cancelled`. The
/// `changed` events arrive at the trackpad's report rate, so acting on each of them would run
/// through all ten workspaces on one flick. Instead the gesture is *armed* by `began`, steps
/// exactly once — on the first event, `began` included, that reports a horizontal motion and a
/// left-or-right mask — and is disarmed by that step or by `ended` / `cancelled`, whichever comes
/// first. Stepping as soon as the direction is known, rather than on `ended`, is what macOS does
/// with the Spaces swipe (it commits when the threshold is crossed, not when the fingers lift),
/// and it also means a missed `ended` — a tap re-armed after a timeout has lost whatever it did
/// not see — costs nothing: the next `began` arms afresh.
///
/// A stepping variant — one workspace per threshold crossed, so a long swipe travels further —
/// wants a real gesture-amount field and is left until this one has been lived with.
public struct DockSwipe: Equatable {

    /// Where the fingers went. Physical, before any scrolling preference: which workspace that
    /// asks for is `WorkspaceTarget.swipe`'s question.
    public enum Direction: Equatable {
        case left
        case right
    }

    /// The values the tap's private fields read, named once here so the selftest feeds the state
    /// machine the same numbers the tap does. Static constants rather than enums with raw values
    /// so that an unrecognised number — a renumbered field on some future macOS — falls through
    /// the `switch` as "neither arms nor releases" rather than failing to construct at all.
    public enum Phase {
        public static let began: Int64 = 1
        public static let changed: Int64 = 2
        public static let ended: Int64 = 4
        public static let cancelled: Int64 = 8
    }

    public enum Motion {
        public static let none: Int64 = 0
        public static let horizontal: Int64 = 1
        public static let vertical: Int64 = 2
    }

    /// A bit set, though a swipe only ever reports one of them.
    public enum Mask {
        public static let up: Int64 = 1
        public static let down: Int64 = 2
        public static let left: Int64 = 4
        public static let right: Int64 = 8
    }

    /// True between `began` and whichever comes first of the step, `ended` and `cancelled`.
    private var armed = false

    public init() {}

    /// Feed every dock swipe event, in order. Answers the direction on the one event that steps.
    ///
    /// Everything short of a positive identification stays quiet *and* stays armed: a horizontal
    /// motion whose mask has not settled yet, a mask with no motion, or both bits set are all
    /// "not yet" rather than "no", and the next `changed` gets to answer. An event with no `began`
    /// before it — the tap was started mid-gesture — is dropped, as is anything after the step.
    public mutating func feed(phase: Int64, swipeMask: Int64, motion: Int64) -> Direction? {
        switch phase {
        case Phase.began: armed = true
        case Phase.ended, Phase.cancelled:
            armed = false
            return nil
        default: break              // `changed`, or a number this code does not know
        }

        guard armed, motion == Motion.horizontal else { return nil }
        let direction: Direction
        switch swipeMask {
        case Mask.left: direction = .left
        case Mask.right: direction = .right
        default: return nil
        }
        armed = false
        return direction
    }
}

extension WorkspaceTarget {
    /// The workspace a sideways swipe asks for: `workspace e+1` / `e-1`, the keyboard's own
    /// next-and-previous-in-use, from the trackpad.
    ///
    /// macOS's Spaces swipe follows System Settings' *Natural scrolling* — content tracks the
    /// fingers, so fingers moving left drag the desktop left and pull the next Space in from the
    /// right — and reverses along with it, which is what anyone who has turned the setting off
    /// expects a sideways swipe to do. So this takes the preference and does the same.
    public static func swipe(_ direction: DockSwipe.Direction, naturalScrolling: Bool) -> WorkspaceTarget {
        switch (direction, naturalScrolling) {
        case (.left, true), (.right, false): return .next
        case (.right, true), (.left, false): return .previous
        }
    }
}
