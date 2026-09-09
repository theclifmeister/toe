import Foundation

/// A named arrangement of windows, saved and put back by name.
///
/// This is the session snapshot's idea with the one thing that makes a session snapshot exact
/// taken out. `SessionSnapshot` is keyed on `CGWindowID`, which the window server keeps stable
/// for the life of a window — so a restart puts every window back with no matching at all, and
/// a reboot invalidates the whole file. A profile has to survive exactly what that cannot: the
/// applications being quit and started again, on another day, with different window ids. So it
/// names windows the way a person would — by application, and by a fragment of the title when
/// the application has more than one window that matters.
///
/// What it therefore records is *placement*: which workspace each window belongs on, in what
/// order, and whether it floats. Not the split ratios. A dwindle tree is built by inserting
/// windows one after another, so replaying the order rebuilds the same shape as long as nobody
/// has since flipped a split by hand — and the alternative, storing ratios against selectors,
/// would put back a geometry for a set of windows that may not all have turned up. Placement is
/// the part that is true whether or not every application in the profile is running.
public struct LayoutProfile: Codable, Equatable, Sendable {

    /// Bumped when the shape below changes incompatibly; an older or newer file is refused
    /// with a sentence rather than half-read.
    public static let currentVersion = 1

    public var version: Int
    public var name: String
    public var savedAt: Date
    public var workspaces: [ProfileWorkspace]

    public init(name: String, savedAt: Date = Date(), workspaces: [ProfileWorkspace] = []) {
        self.version = Self.currentVersion
        self.name = name
        self.savedAt = savedAt
        self.workspaces = workspaces
    }
}

public struct ProfileWorkspace: Codable, Equatable, Sendable {
    public var index: Int
    /// In the order they should be put back: tiles first, left to right through the tree, then
    /// the detached windows. Replaying that order is what reproduces the shape.
    public var windows: [ProfileWindow]

    public init(index: Int, windows: [ProfileWindow]) {
        self.index = index
        self.windows = windows
    }
}

/// One window, named the way it will still be nameable tomorrow.
public struct ProfileWindow: Codable, Equatable, Sendable {
    /// The bundle identifier where there is one — the stable name, and the one `[[float]]`
    /// rules already match on.
    public var bundle: String?
    /// The application's own name, kept as well as the bundle rather than instead of it: it is
    /// what a person reads when they open the file, and it is the fallback for the handful of
    /// processes that have no bundle identifier at all.
    public var app: String
    /// A fragment of the title, and only when the profile needs it to tell two windows of the
    /// same application apart. Written for the *second* window of an application and after,
    /// never for the first — a title is the least durable thing about a window (a browser's is
    /// whatever page it is on), so it earns its place only where nothing else distinguishes.
    public var title: String?
    public var floating: Bool

    public init(bundle: String? = nil, app: String, title: String? = nil, floating: Bool) {
        self.bundle = bundle
        self.app = app
        self.title = title
        self.floating = floating
    }

    /// Whether a live window could be this one. Bundle identifier if the profile has one,
    /// otherwise the application's name; the title fragment narrows it when it is there.
    public func matches(_ window: WindowReport) -> Bool {
        if let bundle {
            guard window.bundle?.compare(bundle, options: .caseInsensitive) == .orderedSame
            else { return false }
        } else {
            guard window.app.compare(app, options: .caseInsensitive) == .orderedSame
            else { return false }
        }
        guard let title else { return true }
        return window.title?.range(of: title, options: .caseInsensitive) != nil
    }
}

/// One window's move, as the app layer should carry it out.
public struct ProfileMove: Equatable, Sendable {
    public var window: WindowID
    public var workspace: Int
    public var floating: Bool

    public init(window: WindowID, workspace: Int, floating: Bool) {
        self.window = window
        self.workspace = workspace
        self.floating = floating
    }
}

/// What applying a profile would do, worked out before anything moves.
public struct ProfilePlan: Equatable, Sendable {
    /// In the order they must be carried out: a workspace's windows are inserted one after
    /// another, and the order is the shape.
    public var moves: [ProfileMove]
    /// Windows the profile names that are not open. Reported rather than swallowed — a profile
    /// half-applied because an application was not running looks identical to a profile that
    /// did not work, and the difference is the whole of what the caller needs to know.
    public var missing: [ProfileWindow]
    /// Open windows the profile says nothing about. Left exactly where they are: a profile is
    /// an arrangement of the windows it names, not a claim about the whole screen, and moving
    /// somebody's unrelated windows out of the way would be the kind of tidying nobody asked
    /// for.
    public var untouched: [WindowID]

    public init(moves: [ProfileMove] = [], missing: [ProfileWindow] = [], untouched: [WindowID] = []) {
        self.moves = moves
        self.missing = missing
        self.untouched = untouched
    }
}

public extension LayoutProfile {

    /// Reads a profile off the current state.
    ///
    /// `windows` must be in the order `WorkspaceReport.windows` gives — tiles in tree order,
    /// then floats — because that order is the whole of what a profile knows about shape.
    static func capture(name: String, from state: StateReport) -> LayoutProfile {
        var profile = LayoutProfile(name: name)
        let byID = Dictionary(state.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for workspace in state.workspaces.sorted(by: { $0.index < $1.index }) {
            var seen: [String: Int] = [:]
            var rows: [ProfileWindow] = []
            for id in workspace.windows {
                guard let window = byID[id] else { continue }
                // The title only from the second window of an application onwards — see
                // `ProfileWindow.title`. The first one of a kind is named by its application,
                // which is both what the user means and the name that will still be true when
                // they come back to it.
                let key = window.bundle ?? window.app
                let count = (seen[key] ?? 0) + 1
                seen[key] = count
                rows.append(ProfileWindow(bundle: window.bundle,
                                          app: window.app,
                                          title: count > 1 ? window.title : nil,
                                          floating: window.floating))
            }
            guard !rows.isEmpty else { continue }
            profile.workspaces.append(ProfileWorkspace(index: workspace.index, windows: rows))
        }
        return profile
    }

    /// Matches the profile against what is open now.
    ///
    /// A live window is claimed at most once and in the order the profile lists them, so two
    /// terminals in a profile take the two terminals that are open, and a profile asking for
    /// three when two are running places two and reports the third as missing rather than
    /// placing one of them twice.
    ///
    /// Windows already on the workspace the profile wants them on still produce a move. The app
    /// layer drops those — it is a `moveWindow` to where the window already is — and the plan is
    /// easier to read as the arrangement it asks for than as a diff against the arrangement
    /// that happens to be there.
    func plan(against windows: [WindowReport]) -> ProfilePlan {
        var plan = ProfilePlan()
        var available = windows.sorted { $0.id < $1.id }
        var claimed: Set<WindowID> = []

        for workspace in workspaces {
            for wanted in workspace.windows {
                guard let hit = available.first(where: { !claimed.contains($0.id) && wanted.matches($0) })
                else {
                    plan.missing.append(wanted)
                    continue
                }
                claimed.insert(hit.id)
                plan.moves.append(ProfileMove(window: hit.id,
                                              workspace: workspace.index,
                                              floating: wanted.floating))
            }
        }

        available.removeAll { claimed.contains($0.id) }
        plan.untouched = available.map(\.id)
        return plan
    }
}

/// What `layout apply` answers with.
public struct LayoutApplyReport: Codable, Equatable, Sendable {
    public var profile: String
    public var moved: [WindowID]
    /// The windows the profile named that are not open, as the profile spells them — enough for
    /// a caller to decide to launch them and try again.
    public var missing: [String]
    public var untouched: [WindowID]

    public init(profile: String, moved: [WindowID], missing: [String], untouched: [WindowID]) {
        self.profile = profile
        self.moved = moved
        self.missing = missing
        self.untouched = untouched
    }

    public init(profile: String, plan: ProfilePlan, moved: [WindowID]) {
        self.profile = profile
        self.moved = moved
        self.missing = plan.missing.map { window in
            window.title.map { "\(window.app) — \($0)" } ?? window.app
        }
        self.untouched = plan.untouched
    }
}
