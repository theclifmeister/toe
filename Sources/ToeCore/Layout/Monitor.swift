import Foundation

/// A display. `usable` is the tiling area — `NSScreen.visibleFrame` converted to
/// Accessibility coordinates, so the menu bar, the Dock and anything else that reserves
/// space (sketchybar included) are already excluded. This is Hyprland's monitor box minus
/// its reserved area.
public struct Monitor: Equatable, Sendable {
    public let id: UInt32          // CGDirectDisplayID
    public var frame: Box
    public var usable: Box

    public init(id: UInt32, frame: Box, usable: Box) {
        self.id = id
        self.frame = frame
        self.usable = usable
    }

    /// The same display with a strip `height` tall reserved along the top of its frame — the
    /// bar's exclusive zone, in Hyprland's words.
    ///
    /// Reserved from the *frame*, not from `usable`: with the menu bar hidden `visibleFrame`
    /// reaches the top of the display and the bar takes the first 26 points of it, but with the
    /// menu bar showing — the bar switched off, or a moment before the hide has propagated —
    /// `usable` already starts below the menu bar, and the tiles would lose 26 points to a bar
    /// that is behind the menu bar anyway. So the reserved strip is measured from the top of
    /// the display and the tiling area keeps whichever of the two starts lower. Nothing
    /// downstream changes: the layout, the floats, the stash corner and the quick menu all key
    /// off `usable` already, which is the whole reason the zone is expressed here.
    ///
    /// A strip taller than the display leaves a zero-height `usable` rather than a negative one.
    public func reserving(top height: Double) -> Monitor {
        guard height > 0 else { return self }
        let top = max(usable.minY, frame.minY + height)
        let bottom = max(top, usable.maxY)
        return Monitor(id: id, frame: frame,
                       usable: Box(x: usable.x, y: top, w: usable.w, h: bottom - top))
    }
}

/// Where a window goes when its workspace is hidden.
///
/// Moving a window far off-screen does **not** work: AppKit's `constrainFrameRect(_:to:)`
/// drags it back until enough of its title bar is reachable, which leaves a wide strip of it
/// visible. Asking for x = -20000 lands at x = -(width - 40).
///
/// The trick is to place the window's *top-left corner* on the monitor's bottom corner. The
/// title bar is then still technically on screen, so nothing is
/// clamped, and all that remains visible is a single pixel.
public enum Stash {

    /// Picks the corner that points away from the other displays, so hidden windows never
    /// spill onto a neighbouring monitor.
    public static func origin(windowSize: Point, on monitor: Monitor, monitors: [Monitor]) -> Point {
        let usable = monitor.usable
        let hasNeighbourToTheRight = monitors.contains {
            $0.id != monitor.id && $0.usable.minX >= usable.maxX - 1
        }

        if hasNeighbourToTheRight {
            // Off to the bottom-left: one pixel of the window's right edge stays on screen.
            return Point(x: usable.minX - windowSize.x + 1, y: usable.maxY - 1)
        }
        // Off to the bottom-right: one pixel of the window's top-left corner stays on screen.
        return Point(x: usable.maxX - 1, y: usable.maxY - 1)
    }
}
