import Foundation

/// Where a floating window belongs in the stack, and how to get it there.
///
/// Hyprland draws every floating window above the tiles, always. toe cannot: Accessibility
/// has a raise action and no lower, so the only way to send a window back is to raise what
/// sits over it. That leaves a rule of its own, and a better one for a keyboard: the float
/// stays on top while it holds the focus, and goes behind the moment it loses it — so
/// cycling along the grid with `SUPER`+arrows never lands on a tile half-covered by a window
/// the user has already moved on from.
public enum Stacking {

    /// The windows to raise, in the order to raise them — the last one ends up in front.
    ///
    /// Empty when nothing has to move, which is every focus change with no unfocused float on
    /// screen, so the caller leaves the stack alone in the ordinary case.
    ///
    /// Only the tiles a float actually covers are raised. Tiles never overlap each other, so
    /// re-ordering those among themselves is invisible, and leaving the rest where they are
    /// keeps this to the Accessibility calls the change really needs.
    ///
    /// A float already under everything it covers is left alone — which is the answer most of
    /// the time, and the difference between correcting the stack and churning it. That has to
    /// be asked of the window server rather than remembered, because toe is not the only thing
    /// that re-orders windows: activating an application brings its windows forward as a group,
    /// so focusing a tile can lift a float belonging to the same application right back up.
    ///
    /// - Parameters:
    ///   - tiles: tiled windows on a visible workspace, and the frame each occupies.
    ///   - floats: floating windows on a visible workspace, and the frame each occupies.
    ///   - focused: the window that holds the focus, which ends up in front of the lot.
    ///   - stackedAbove: the windows currently above the given one, asked only about floats
    ///     that have lost the focus, and only when there are any.
    public static func raiseOrder(tiles: [WindowID: Box],
                                  floats: [WindowID: Box],
                                  focused: WindowID?,
                                  stackedAbove: (WindowID) -> Set<WindowID> = { _ in [] })
    -> [WindowID] {
        let sinking = floats.filter { $0.key != focused }
        guard !sinking.isEmpty else { return [] }

        var covered: Set<WindowID> = []
        for (float, frame) in sinking {
            let over = tiles.filter { overlaps(frame, $0.value) }.keys
            guard !over.isEmpty else { continue }
            // Already at the bottom of everything it covers: nothing to do for this one.
            if over.allSatisfy(stackedAbove(float).contains) { continue }
            covered.formUnion(over)
        }
        guard !covered.isEmpty else { return [] }

        // Sorted only so the order is the same twice running: which tile goes above which
        // cannot be seen, and a stable answer is what makes this testable.
        var order = covered.sorted()
        // The focused window last, whether or not a float covers it. It is the one place in
        // the stack anybody can see, and raising the tiles under a float would otherwise
        // bury a focused float along with them.
        if let focused, tiles[focused] != nil || floats[focused] != nil {
            order.removeAll { $0 == focused }
            order.append(focused)
        }
        return order
    }

    /// Overlap worth acting on. Frames that merely share an edge are the tiling grid meeting
    /// itself, and a sliver of a point is the difference between Accessibility's idea of a
    /// frame and the window server's — neither is a window covering another one.
    private static func overlaps(_ a: Box, _ b: Box) -> Bool {
        let clipped = a.intersection(b)
        return clipped.w > 1 && clipped.h > 1
    }
}
