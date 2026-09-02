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
