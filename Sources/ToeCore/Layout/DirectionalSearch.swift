import Foundation

/// Port of `CCompositor::getWindowInDirection` for tiled windows
/// (`binds:focus_preferred_method = 0`, Hyprland's default: history tie-break).
///
/// Tiles only. A detached window is not on the grid — `togglefloating` centres it, so its
/// edges land inside tiles rather than against them, and two of a size land on top of each
/// other — so `WorkspaceManager` walks those as a list instead of asking geometry a question
/// it cannot answer.
///
/// Two things make this different from every "nearest window" heuristic, and both matter
/// for matching Hyprland exactly:
///
///  1. A candidate only qualifies if its opposing edge *sticks* to ours (within 2px) — so
///     focus walks the tiling grid rather than jumping across it. This must be run on the
///     un-gapped node boxes, otherwise the gaps break every adjacency.
///  2. Among qualifying candidates, the winner is the most recently focused one, not the
///     one with the largest shared edge.
///
/// That second rule is `focus_preferred_method = 0` and nothing else: there is no switch here
/// for `= 1` (longest shared edge). One used to be declared and never passed, and its branch
/// had quietly diverged from this one — it accepted a candidate whose edges merely touched at a
/// corner, where the live path demands a real overlap. In the one file whose whole point is
/// fidelity to upstream, an untested second mode is a liability; it can come back with its test
/// on the day it is wanted.
public enum DirectionalSearch {

    public static func windowInDirection(
        from origin: Box,
        ignoring: WindowID?,
        candidates: [(id: WindowID, box: Box)],
        direction: Direction,
        focusHistory: [WindowID]
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

            // A real shared edge, not a corner that happens to touch.
            guard intersectLength > 0 else { continue }
            // Most recently focused wins. History is ordered most-recent-first.
            let idx = focusHistory.firstIndex(of: candidate.id) ?? focusHistory.count
            let score = Double(focusHistory.count - idx)
            if score > leaderValue {
                leaderValue = score
                leader = candidate.id
            }
        }

        return leaderValue != -1 ? leader : nil
    }
}
