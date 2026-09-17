import Foundation

/// Whether `killactive` closes the window or quits the application it belongs to — decided
/// here so the selftest can reach it, with the Accessibility lookup and the terminate left in
/// `toe` (#156).
///
/// On macOS an application whose last window closes keeps running, with a menu bar and a Dock
/// light and nothing to show for it, and the next thing anybody does is reach for ⌘Q — the
/// reflex SUPER+W was bound to replace. On Omarchy a program with no window is a program that
/// has exited, so on the last window toe sends the quit instead. *Instead of* rather than after:
/// the close button and then a terminate would kill the "save changes?" sheet the close put up,
/// and "did the close land, is the application empty now" is a race against the application's
/// own event loop that need not be run. `NSRunningApplication.terminate()` is the quit Apple
/// Event — the thing ⌘Q sends — so the application closes its own window, asks its own
/// questions, and the user can still say no.
///
/// The one outcome this must never produce is quitting an application that had another
/// window, so every doubt resolves to `.closeWindow`. "Last" is app-wide: a Safari window
/// stashed on workspace 3, floating, minimized, or in native fullscreen on a Space of its own is
/// still a Safari window, which is why the count is the application's own `kAXWindows` list
/// and not the workspace tree or the tracker — the tracker only knows what `isManageable` let
/// it adopt, and a Preferences window it never took is a window ⌘Q would still close.
public enum CloseVerdict: Equatable {
    /// Press the close button. Every case that is not provably the other one.
    case closeWindow
    /// Send the application a quit and let it close the window itself.
    case quitApplication

    /// What the application says about itself, gathered by the caller.
    public struct Application: Equatable {
        public var bundleID: String?
        /// The id of every window the application reports, on any Space, minimized or not. An
        /// entry is `nil` when a window would not say — and a window that would not say might
        /// be a second one, so the answer is then `.closeWindow`.
        public var windows: [WindowID?]
        /// Whether the application is an ordinary one — `activationPolicy == .regular`, a Dock
        /// tile and a menu bar. An accessory or a background process has no ⌘Q to stand in for
        /// and only ever loses the window.
        public var ordinary: Bool

        public init(bundleID: String?, windows: [WindowID?], ordinary: Bool) {
            self.bundleID = bundleID
            self.windows = windows
            self.ordinary = ordinary
        }
    }

    /// Applications that are never quit, whatever the count. The Finder has no ⌘Q at all —
    /// closing its last window is closing a window, and a terminate would relaunch it.
    public static let neverQuit: Set<String> = ["com.apple.finder"]

    /// `app` is an autoclosure so the switch is consulted before a single Accessibility call is
    /// made on its behalf: gathering the window list is one round trip per window, and with the
    /// setting off there is nothing to decide.
    public static func decide(closing id: WindowID, of app: @autoclosure () -> Application,
                              quitOnLastWindow: Bool) -> CloseVerdict {
        guard quitOnLastWindow else { return .closeWindow }
        let app = app()
        guard app.ordinary else { return .closeWindow }
        if let bundleID = app.bundleID, neverQuit.contains(bundleID) { return .closeWindow }
        // Exactly this window and nothing else: an empty list is an application that would not
        // answer, a list without this window is one whose answer cannot be trusted, and either
        // is a doubt.
        guard app.windows.count == 1, app.windows[0] == id else { return .closeWindow }
        return .quitApplication
    }
}
