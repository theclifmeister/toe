import Foundation

/// Port of `CCompositor::getWindowInDirection` for tiled windows
/// (`binds:focus_preferred_method = 0`, Hyprland's default: history tie-break).
///
/// Two things make this different from every "nearest window" heuristic, and both matter
/// for matching Hyprland exactly:
///
///  1. A candidate only qualifies if its opposing edge *sticks* to ours (within 2px) — so
///     focus walks the tiling grid rather than jumping across it. This must be run on the
///     un-gapped node boxes, otherwise the gaps break every adjacency.
///  2. Among qualifying candidates, the winner is the most recently focused one, not the
///     one with the largest shared edge.
public enum DirectionalSearch {

    public static func windowInDirection(
        from origin: Box,
        ignoring: WindowID?,
        candidates: [(id: WindowID, box: Box)],
        direction: Direction,
        focusHistory: [WindowID],
        preferLongestSharedEdge: Bool = false
    ) -> WindowID? {

        var leaderValue: Double = -1
        var leader: WindowID?

        for candidate in candidates {
            if let ignoring, candidate.id == ignoring { continue }

            let b = candidate.box
            var intersectLength: Double = -1

            switch direction {
            case .left:
                if STICKS(origin.minX, b.maxX) {
                    intersectLength = max(0, min(origin.maxY, b.maxY) - max(origin.minY, b.minY))
                }
            case .right:
                if STICKS(origin.maxX, b.minX) {
                    intersectLength = max(0, min(origin.maxY, b.maxY) - max(origin.minY, b.minY))
                }
            case .up:
                if STICKS(origin.minY, b.maxY) {
                    intersectLength = max(0, min(origin.maxX, b.maxX) - max(origin.minX, b.minX))
                }
            case .down:
                if STICKS(origin.maxY, b.minY) {
                    intersectLength = max(0, min(origin.maxX, b.maxX) - max(origin.minX, b.minX))
                }
            }

            if preferLongestSharedEdge {
                if intersectLength > leaderValue {
                    leaderValue = intersectLength
                    leader = candidate.id
                }
            } else {
                guard intersectLength > 0 else { continue }
                // Most recently focused wins. History is ordered most-recent-first.
                let idx = focusHistory.firstIndex(of: candidate.id) ?? focusHistory.count
                let score = Double(focusHistory.count - idx)
                if score > leaderValue {
                    leaderValue = score
                    leader = candidate.id
                }
            }
        }

        return leaderValue != -1 ? leader : nil
    }

    /// The search floating windows are found with, since they never touch the grid.
    ///
    /// `windowInDirection` walks the tiling grid by edge adjacency, and a window floating in
    /// the middle of the screen sticks to nothing — `togglefloating` centres it, so its edges
    /// land inside tiles rather than against them. It qualifies here instead: a candidate is
    /// in `direction` when its centre lies inside the 90° cone opening that way from ours,
    /// and the nearest centre wins, focus history breaking a tie. The distance comes back
    /// with the winner so the caller can weigh it against what the grid walk found.
    ///
    /// A window stacked right on top of us — a float centred over the single tile it left
    /// behind, the two centres one point — lies in no direction at all. Rather than strand
    /// it, it comes back flagged `stacked`, for the caller to use only where nothing else
    /// answers: it is a last resort, never something that outranks a real neighbour. It is
    /// exactly that degenerate case, the two centres within `STICKS` of each other, and
    /// nothing wider: a window merely overlapping ours still lies somewhere, and answering
    /// with one that sits below and to the left of a press of `up` is worse than not moving.
    public static func nearestInDirection(
        from origin: Box,
        ignoring: WindowID?,
        candidates: [(id: WindowID, box: Box)],
        direction: Direction,
        focusHistory: [WindowID]
    ) -> (id: WindowID, distance: Double, stacked: Bool)? {

        let a = origin.middle
        var leader: WindowID?
        var leaderDistance = Double.infinity
        var leaderRecency = -1
        var stacked: WindowID?
        var stackedRecency = -1

        for candidate in candidates {
            if let ignoring, candidate.id == ignoring { continue }

            let b = candidate.box.middle
            let dx = b.x - a.x
            let dy = b.y - a.y
            // History is ordered most-recent-first; a window not in it sorts last.
            let idx = focusHistory.firstIndex(of: candidate.id) ?? focusHistory.count
            let recency = focusHistory.count - idx

            let along: Double
            switch direction {
            case .left:  along = -dx
            case .right: along = dx
            case .up:    along = -dy
            case .down:  along = dy
            }
            let across = (direction == .left || direction == .right) ? abs(dy) : abs(dx)

            guard along > 0, along >= across else {
                if STICKS(dx, 0), STICKS(dy, 0), recency > stackedRecency {
                    stackedRecency = recency
                    stacked = candidate.id
                }
                continue
            }

            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < leaderDistance || (distance == leaderDistance && recency > leaderRecency) {
                leaderDistance = distance
                leaderRecency = recency
                leader = candidate.id
            }
        }

        if let leader { return (id: leader, distance: leaderDistance, stacked: false) }
        return stacked.map { (id: $0, distance: .infinity, stacked: true) }
    }
}
