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

    /// Fires for each pointer move while a drag is live, with the window being dragged.
    var onMove: ((WindowID, Point) -> Void)?
    /// Fires when the user lets go, so whatever was hidden can come back.
    var onEnd: ((WindowID) -> Void)?

    private(set) var isDragging = false
    /// The window in the user's hand, for as long as they have hold of it.
    private(set) var window: WindowID?
    private var monitors: [Any] = []

    /// Records a window moving or resizing on its own, and reports whether the user is dragging
    /// it: a held mouse button means the hand on the window is the user's.
    ///
    /// Polling the button here rather than tracking mouse-downs keeps the state honest — the
    /// answer is read from the system every time, so a missed release cannot strand the drag.
    @discardableResult
    func noteExternalFrameChange(_ id: WindowID) -> Bool {
        if NSEvent.pressedMouseButtons != 0 { begin(id) } else { end() }
        return isDragging
    }

    private func begin(_ id: WindowID) {
        guard !isDragging else { return }
        isDragging = true
        window = id
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
        isDragging = false
        window = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        onEnd?(dragged)
    }
}
