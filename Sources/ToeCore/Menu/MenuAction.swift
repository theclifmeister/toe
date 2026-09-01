import Foundation

/// Everything a quick menu row can do, as data rather than as a closure.
///
/// Anything a hotkey can already do arrives as `.command`, so those rows take the identical path
/// through `Coordinator.dispatch` — there is no parallel implementation of any dispatcher.
public enum MenuAction: Equatable {
    case command(Command)
    /// Switch to the window's workspace if it is hidden, then focus it. The menu bar's window
    /// rows already do exactly this; both call `Coordinator.reveal(_:)`.
    case revealWindow(WindowID)

    // Style. Each writes ~/.config/toe/toe.toml and lets ConfigWatcher reload it.
    case applyBorderTheme(BorderTheme)
    case applyGaps(inner: Int, outer: Int)
    case setBorderEnabled(Bool)

    // Setup
    case reveal(RevealTarget)
    case setStartAtLogin(Bool)
    case removeLegacyLaunchAgent

    // System
    case system(SystemAction)
    case restartToe
    case quitToe

    // About
    case openURL(String)
    case copyToClipboard(String)

    /// Unused until the Apps section lands; the shape is fixed now so that change is additive.
    case launchApp(bundlePath: String)
}

public enum RevealTarget: Equatable {
    case configFile
    case configFolder
    case accessibilitySettings
}

/// The macOS equivalents of Omarchy's system menu.
///
/// There is no public lock API. `SACLockScreenImmediate` via `dlopen` on `login.framework` would
/// work, but it would be off-key in a project whose README makes a point of *not* reaching for
/// private SkyLight calls; `CGSession -suspend` is fast user switching rather than locking, and its
/// `User.menu` host no longer ships on macOS 26 anyway. So `lock` sends ⌃⌘Q — the same thing the
/// user's own fingers would do, through the Accessibility grant toe already holds.
public enum SystemAction: String, Equatable, CaseIterable {
    case lock
    case sleepDisplay
    case sleep
    case logOut
    case restart
    case shutDown

    public var title: String {
        switch self {
        case .lock:         return "Lock screen"
        case .sleepDisplay: return "Sleep display"
        case .sleep:        return "Sleep"
        case .logOut:       return "Log out…"
        case .restart:      return "Restart…"
        case .shutDown:     return "Shut down…"
        }
    }

    /// Policy as pure data; only the `NSAlert` lives in the app layer.
    ///
    /// `restart` and `shutDown` sent as System Events commands go straight through without the
    /// Apple menu's own confirmation, so they need ours. `logOut` *does* raise the system dialog,
    /// so confirming it here would double up.
    public var needsConfirmation: Bool {
        self == .restart || self == .shutDown
    }

    public var confirmationVerb: String {
        switch self {
        case .restart:  return "Restart"
        case .shutDown: return "Shut Down"
        default:        return title
        }
    }

    public var confirmationMessage: String {
        switch self {
        case .restart:  return "Restart your Mac? Applications will be asked to close."
        case .shutDown: return "Shut down your Mac? Applications will be asked to close."
        default:        return title
        }
    }
}
