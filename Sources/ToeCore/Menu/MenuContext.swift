import Foundation

/// One installed application, for the Apps section.
public struct AppEntry: Equatable, Comparable {
    public let name: String
    public let bundlePath: String
    public init(name: String, bundlePath: String) {
        self.name = name
        self.bundlePath = bundlePath
    }
    public static func < (a: AppEntry, b: AppEntry) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

/// Whether toe launches at login, and by which of the two mechanisms.
public enum StartAtLoginState: Equatable {
    case on
    case off
    /// `make start-at-login` wrote a LaunchAgent. Registering `SMAppService` on top of it would
    /// launch a *second* toe, and two instances fight over every window — so the toggle is shown
    /// disabled and a row offers to remove the plist instead.
    case legacyLaunchAgent
    case unavailable
}

/// Everything the tree is built from, gathered the moment the menu opens.
///
/// Nothing is cached between opens — the same discipline `StatusItem.menuNeedsUpdate` already
/// keeps, and the reason the whole tree can be a pure function of this value.
public struct MenuContext: Equatable {
    public var workspaces: [WorkspaceSummary]
    public var focusedWindow: WindowID?
    public var focusedWorkspace: Int
    /// For `isOn` state and for showing the user's own shortcut beside a command.
    public var config: Config
    public var version: String
    public var startAtLogin: StartAtLoginState
    /// Empty until the Apps section lands.
    public var apps: [AppEntry]

    public init(workspaces: [WorkspaceSummary] = [],
                focusedWindow: WindowID? = nil,
                focusedWorkspace: Int = 1,
                config: Config = Config(),
                version: String = "unknown",
                startAtLogin: StartAtLoginState = .off,
                apps: [AppEntry] = []) {
        self.workspaces = workspaces
        self.focusedWindow = focusedWindow
        self.focusedWorkspace = focusedWorkspace
        self.config = config
        self.version = version
        self.startAtLogin = startAtLogin
        self.apps = apps
    }

    public static let empty = MenuContext()

    public var hasFocusedWindow: Bool { focusedWindow != nil }

    /// The user's own shortcut for a command, so a menu row never claims a binding they have
    /// rebound. Nil when nothing is bound to it.
    public func shortcut(for command: Command) -> String? {
        config.bindings.first { $0.command == command }?.describedShortcut
    }

    public func workspace(_ index: Int) -> WorkspaceSummary? {
        workspaces.first { $0.index == index }
    }
}
