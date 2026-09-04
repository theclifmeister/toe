import AppKit
import ToeCore

/// Tells a window move the user is making by hand from one an app — or toe — made on its own,
/// and follows the pointer for as long as it lasts.
///
/// toe learns about moves from Accessibility notifications, which arrive well behind the window
/// itself, so anything drawn around a window trails it across the screen for as long as the drag
/// lasts, so for the duration the border marks the tile the window will land in instead — which
/// is somewhere toe knows exactly. The pointer, on the other hand,
/// can be read live — which is what lets a tiled window trade places with the tile it is dragged
/// over, the way Hyprland's `IHyprLayout::onMouseMove` does.
final class DragMonitor {

    /// What the user has hold of: the window, or one of its edges.
    ///
    /// A drag starts as a move and is *promoted* to a resize by the first Resized notification
    /// that arrives while it is live — never the other way — because the alternative, comparing
    /// sizes when the drag begins, does not work: the first notification of a slow edge-drag is
    /// a pixel in, under any tolerance, and `begin` runs once, so a resize taken for a move
    /// would stay one for the whole drag while `onMove` traded the window with every tile the
    /// pointer touched. The notification is the fact; the frame is only a consequence of it.
    enum Kind {
        case move
        case resize
    }

    /// Fires for each pointer move while a drag is live, with the window being dragged.
    var onMove: ((WindowID, Point) -> Void)?
    /// Fires when the user lets go, so whatever was hidden can come back — with what the drag
    /// knew, because `end` has cleared it by the time the closure runs.
    var onEnd: ((WindowID, Kind, Box?) -> Void)?

    private(set) var isDragging = false
    /// The window in the user's hand, for as long as they have hold of it.
    private(set) var window: WindowID?
    private(set) var kind: Kind = .move
    /// The tile the window was in when the user took hold of it. A resize is measured against
    /// this on release rather than against the tile the coordinator currently wants, because
    /// that one moves under a live drag — a window opening next to the dragged one, or a
    /// neighbour closing, re-lays the tree out and the dragged window's tile with it. What
    /// the user's hand did is relative to what they saw when they reached for the edge;
    /// Hyprland's `m_vBeginDragSizeXY` is the same idea. Nil for a float, which has no tile.
    private(set) var origin: Box?
    private var monitors: [Any] = []

    /// Records a window moving or resizing on its own, and reports whether the user is dragging
    /// it: a held mouse button means the hand on the window is the user's.
    ///
    /// Polling the button here rather than tracking mouse-downs keeps the state honest — the
    /// answer is read from the system every time, so a missed release cannot strand the drag.
    ///
    /// - Parameters:
    ///   - resized: whether this was the Resized notification rather than the Moved one; see
    ///     `Kind` for why one of them is enough to promote the drag for good.
    ///   - tile: the frame the coordinator had written for the window. Read once, at `begin`.
    @discardableResult
    func noteExternalFrameChange(_ id: WindowID, resized: Bool, tile: Box?) -> Bool {
        if NSEvent.pressedMouseButtons != 0 {
            begin(id, tile: tile)
            if resized, id == window { kind = .resize }
        } else {
            end()
        }
        return isDragging
    }

    private func begin(_ id: WindowID, tile: Box?) {
        guard !isDragging else { return }
        isDragging = true
        window = id
        kind = .move
        origin = tile
        // toe never sees the drag itself: the events all belong to the window's own application.
        // Global monitors are read-only and consume nothing, which keeps the pointer readable
        // without widening the one tap toe does run — `DockSwipeTap`, whose mask admits gesture
        // events only and could not carry a mouse event if it wanted to.
        add([.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] _ in self?.end() }
        add([.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            guard let self, let window = self.window else { return }
            self.onMove?(window, Coordinates.toAX(NSEvent.mouseLocation))
        }
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(monitor)
        }
    }

    private func end() {
        guard isDragging, let dragged = window else { return }
        let (how, from) = (kind, origin)
        isDragging = false
        window = nil
        kind = .move
        origin = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        onEnd?(dragged, how, from)
    }
}
