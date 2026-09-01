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
}
