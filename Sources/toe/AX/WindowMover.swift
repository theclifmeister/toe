import AppKit
import ApplicationServices
import ToeCore

enum WindowMover {

    /// Writes a frame to a window.
    ///
    /// Two things are load-bearing here:
    ///
    ///  * **position → size → position.** AppKit resolves size constraints against the current
    ///    position, so a single pass lands short whenever a window is being moved and resized
    ///    at once. The second position write settles it.
    ///  * **AXEnhancedUserInterface.** Chromium and Electron apps (Chrome, VS Code, Slack) and
    ///    the JetBrains IDEs turn this on for assistive tech; while it is on they animate or
    ///    silently ignore programmatic resizes. Turning it off around the write and restoring
    ///    it afterwards is what makes those apps tile at all.
    static func setFrame(_ frame: Box, element: AXUIElement, pid: pid_t) {
        let app = AX.application(pid)
        let enhanced = app.bool(kAXEnhancedUserInterface) ?? false
        if enhanced { app.set(kAXEnhancedUserInterface, kCFBooleanFalse) }
        defer { if enhanced { app.set(kAXEnhancedUserInterface, kCFBooleanTrue) } }

        let origin = CGPoint(x: frame.x, y: frame.y)
        let size = CGSize(width: frame.w, height: frame.h)

        element.setPosition(origin)
        element.setSize(size)
        element.setPosition(origin)
    }

    /// Moves a window without touching its size, used for stashing and un-stashing.
    static func setPosition(_ point: CGPoint, element: AXUIElement, pid: pid_t) {
        let app = AX.application(pid)
        let enhanced = app.bool(kAXEnhancedUserInterface) ?? false
        if enhanced { app.set(kAXEnhancedUserInterface, kCFBooleanFalse) }
        defer { if enhanced { app.set(kAXEnhancedUserInterface, kCFBooleanTrue) } }
        element.setPosition(point)
    }

    static func focus(_ window: ManagedWindow) {
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        window.element.set(kAXFocusedAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    static func close(_ window: ManagedWindow) {
        guard let button = window.element.elementValue(kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }
}

let kAXEnhancedUserInterface = "AXEnhancedUserInterface"
