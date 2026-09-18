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
        raise(window)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    /// Stacking only: no `kAXMain`, no `kAXFocused`, no activation. Raising a window does not
    /// make its application the active one, which is what lets toe lift a tile over a float
    /// belonging to some other app without taking the focus off either of them.
    static func raise(_ window: ManagedWindow) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    static func close(_ window: ManagedWindow) {
        guard let button = window.element.elementValue(kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// Asks the application to quit — `terminate()`, the quit Apple Event ⌘Q sends, so the
    /// application closes its own windows and puts up its own "save changes?" first. Never
    /// `forceTerminate()`: this is a window manager closing a window, not a kill. (`AppIdentity`
    /// avoids `terminate()` for toe's *own* other copy because AppKit answers the event without
    /// going near `shutDown`; that is about toe, and here the event is the point.)
    ///
    /// `application`, not the pid: a Steam window belongs to Steam Helper, and a quit sent to
    /// the helper alone takes the UI down and leaves the client running headless. The owner's
    /// record has `processIdentifier == -1` and `terminate()` on it quits Steam all the same
    /// (#158, verified).
    static func quit(_ window: ManagedWindow) {
        window.application?.terminate()
    }

    /// What `CloseVerdict` needs to know about the application a window belongs to, gathered
    /// only when the verdict asks — one round trip for the window list and one per window for
    /// its id, on a keypress. The application's own `kAXWindows`, not the tracker's, because
    /// the tracker only holds what `isManageable` let it adopt, and a minimized window or a
    /// Preferences panel it never took is a window ⌘Q would close (#156). `kAXWindows` lists a
    /// window on any Space, which is what makes a fullscreen sibling on a Space of its own count.
    /// The size is what lets the verdict discount Steam's 1×1 helper window — see `Sibling`.
    ///
    /// For a helper's window the application is the owner — its bundle identifier, its
    /// activation policy, and the quit goes to it — and the window list is the union of the
    /// owner's and the helper's: Steam's real windows are the helper's, and the 1×1 window is
    /// `steam_osx`'s own, and "is this the last one" is asked of both (#158).
    static func application(of window: ManagedWindow) -> CloseVerdict.Application {
        let app = window.application
        var elements = AX.application(window.pid).windows
        if let owner = window.owner { elements += AX.application(owner.pid).windows }
        return CloseVerdict.Application(
            bundleID: app?.bundleIdentifier ?? window.bundleID,
            windows: elements.map {
                CloseVerdict.Sibling(id: $0.windowID,
                                     size: $0.size.map { CloseVerdict.Size(w: $0.width, h: $0.height) })
            },
            ordinary: app?.activationPolicy == .regular)
    }
}

let kAXEnhancedUserInterface = "AXEnhancedUserInterface"
