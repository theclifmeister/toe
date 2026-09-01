import Foundation

/// One application's presence on a workspace.
///
/// Carries `pid` rather than an `NSImage`: the icon is resolved where it is drawn, via
/// `MenuIcon.runningApp(pid:)`. That one field was the only AppKit thing in here, and without it
/// both of these become pure data that the quick menu's tree can be built from — which is the
/// whole reason they moved out of `StatusItem`.
public struct AppSummary: Equatable {
    public let name: String
    public let windowCount: Int
    public let pid: Int32
    /// Selecting the row focuses this window.
    public let representativeWindow: WindowID
    /// The representative window's title, read fresh when the summary is built.
    public let windowTitle: String?

    public init(name: String, windowCount: Int, pid: Int32,
                representativeWindow: WindowID, windowTitle: String? = nil) {
        self.name = name
        self.windowCount = windowCount
        self.pid = pid
        self.representativeWindow = representativeWindow
        self.windowTitle = windowTitle
    }
}

public struct WorkspaceSummary: Equatable {
    public let index: Int
    /// Shown on the monitor that currently has focus.
    public let isFocused: Bool
    /// Shown on some monitor — with several displays, more than one workspace is visible.
    public let isVisible: Bool
    public let monitorName: String?
    public let apps: [AppSummary]

    public init(index: Int, isFocused: Bool, isVisible: Bool,
                monitorName: String?, apps: [AppSummary]) {
        self.index = index
        self.isFocused = isFocused
        self.isVisible = isVisible
        self.monitorName = monitorName
        self.apps = apps
    }

    public var isEmpty: Bool { apps.isEmpty }
    public var windowCount: Int { apps.reduce(0) { $0 + $1.windowCount } }

    public var stripState: WorkspaceStrip.State {
        .init(index: index, isFocused: isFocused, isVisible: isVisible, isEmpty: isEmpty)
    }
}
