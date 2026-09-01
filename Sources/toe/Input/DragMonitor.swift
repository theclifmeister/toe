import AppKit

/// Tells a window move the user is making by hand from one an app — or toe — made on its own.
///
/// toe learns about moves from Accessibility notifications, which arrive well behind the window
/// itself, so anything drawn around a window trails it across the screen for as long as the drag
/// lasts. The focus border is hidden for the duration instead.
final class DragMonitor {

    /// Fires when the user lets go, so whatever was hidden can come back.
    var onEnd: (() -> Void)?

    private(set) var isDragging = false
    private var mouseUp: Any?

    /// Records a window moving or resizing on its own, and reports whether the user is dragging
    /// it: a held mouse button means the hand on the window is the user's.
    ///
    /// Polling the button here rather than tracking mouse-downs keeps the state honest — the
    /// answer is read from the system every time, so a missed release cannot strand the drag.
    @discardableResult
    func noteExternalFrameChange() -> Bool {
        if NSEvent.pressedMouseButtons != 0 { begin() } else { end() }
        return isDragging
    }

    private func begin() {
        guard !isDragging else { return }
        isDragging = true
        // toe never sees the drag itself: the events all belong to the window's own application.
        mouseUp = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] _ in self?.end() }
    }

    private func end() {
        guard isDragging else { return }
        isDragging = false
        if let mouseUp { NSEvent.removeMonitor(mouseUp) }
        mouseUp = nil
        onEnd?()
    }
}
