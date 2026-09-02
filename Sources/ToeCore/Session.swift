import Foundation

/// A layout written to disk so that a restart can put it back.
///
/// Identity is the `WindowID` itself. A `CGWindowID` is issued by the window server and stays
/// with the window for as long as it exists, whatever happens to toe — so a snapshot taken
/// before a restart names exactly the same windows afterwards and restoring needs no matching
/// heuristics at all. Everything survives verbatim: which workspace a window was on, its slot
/// in the dwindle tree, every split orientation and ratio, and the frames floating windows
/// return to.
///
/// The one thing that invalidates all of it is a reboot, after which those numbers belong to
/// entirely different windows. `boot` is the guard: the app layer fills it with a token
/// identifying the boot the ids came from, and a snapshot whose token no longer matches is
/// discarded unread. That is exact rather than a guess at an expiry, which is why there is no
/// age limit here — a Mac left running for a fortnight has the same window ids it started
/// with, and its snapshot is as good on day fourteen as on day one.
///
/// Monitors are named by an opaque key rather than by `CGDirectDisplayID`, for the same
/// reason `cursorLocation` is a closure: ToeCore does not know what a display is. The app
/// layer hands over a key that survives a replug and maps it back on the way in.
public struct SessionSnapshot: Codable, Equatable {

    /// Bumped when the shape below changes incompatibly. An older or newer file is discarded.
    public static let currentVersion = 1

    public var version: Int
    /// Opaque token for the boot these window ids came from. See the note above.
    public var boot: String
    public var savedAt: Date
    public var workspaces: [WorkspaceSnapshot]
    /// Monitor key -> the workspace index that monitor was showing.
    public var active: [String: Int]
    /// Monitor key -> the workspace `workspace former` would go back to.
    public var previous: [String: Int]
    public var focusedMonitor: String?
    /// Most-recent-first, as `WorkspaceManager.focusHistory` keeps it.
    public var focusHistory: [WindowID]
    public var floatingFrames: [FloatingFrame]

    public init(boot: String,
                savedAt: Date = Date(),
                workspaces: [WorkspaceSnapshot] = [],
                active: [String: Int] = [:],
                previous: [String: Int] = [:],
                focusedMonitor: String? = nil,
                focusHistory: [WindowID] = [],
                floatingFrames: [FloatingFrame] = []) {
        self.version = Self.currentVersion
        self.boot = boot
        self.savedAt = savedAt
        self.workspaces = workspaces
        self.active = active
        self.previous = previous
        self.focusedMonitor = focusedMonitor
        self.focusHistory = focusHistory
        self.floatingFrames = floatingFrames
    }
}

/// Where a floating window goes when its workspace comes back — `m_vLastFloatingPosition`
/// and `..Size`, kept as one record so the file stays readable.
public struct FloatingFrame: Codable, Equatable {
    public var window: WindowID
    public var frame: Box
    /// Where the window is on `togglefloating`'s cycle, so the next press after a restart
    /// carries on round it rather than starting over. Absent for a window the app layer
    /// floated on its own, and for files written before the cycle existed — both of which
    /// mean the same thing, that the next press tiles the window.
    public var stage: Int?

    public init(window: WindowID, frame: Box, stage: Int? = nil) {
        self.window = window
        self.frame = frame
        self.stage = stage
    }
}

public struct WorkspaceSnapshot: Codable, Equatable {
    public var index: Int
    /// The opaque monitor key this workspace lived on.
    public var monitor: String
    public var layout: LayoutSnapshot
    public var floating: [WindowID]

    public init(index: Int, monitor: String, layout: LayoutSnapshot, floating: [WindowID]) {
        self.index = index
        self.monitor = monitor
        self.layout = layout
        self.floating = floating
    }
}

/// One dwindle tree. Node boxes are deliberately absent: they are derived from the monitor's
/// usable area by `recalculate()`, so a snapshot restored onto a different display geometry
/// reflows into it rather than dragging the old screen's coordinates along.
public struct LayoutSnapshot: Codable, Equatable {
    public var root: NodeSnapshot?
    /// Creation order, which the insertion fail-safe reads.
    public var order: [WindowID]

    public init(root: NodeSnapshot? = nil, order: [WindowID] = []) {
        self.root = root
        self.order = order
    }
}

public struct NodeSnapshot: Codable, Equatable {
    /// Set on leaves, nil on internal nodes.
    public var window: WindowID?
    public var splitTop: Bool
    public var splitRatio: Double
    /// Empty on leaves, two entries on an internal node.
    public var children: [NodeSnapshot]

    public init(window: WindowID? = nil,
                splitTop: Bool = false,
                splitRatio: Double = 1.0,
                children: [NodeSnapshot] = []) {
        self.window = window
        self.splitTop = splitTop
        self.splitRatio = splitRatio
        self.children = children
    }

    /// How deep a tree may go before restore stops descending. A dwindle tree only reaches
    /// depth *n* with *n* windows in a degenerate chain, so this is far past anything real —
    /// it is here because the file is decoded before it is trusted, the same reason the TOML
    /// parser caps its own nesting.
    public static let maxDepth = 64
}

public extension NodeSnapshot {
    /// Capture a live node and everything under it.
    init(_ node: DwindleNode) {
        self.init(window: node.window,
                  splitTop: node.splitTop,
                  splitRatio: node.splitRatio,
                  children: node.children.map(NodeSnapshot.init))
    }
}
