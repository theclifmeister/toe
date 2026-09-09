import Foundation

/// The wire between the `toe` you type and the `toe` that is running.
///
/// One line of JSON in, one line of JSON out, over a Unix socket — Hyprland's `hyprctl`
/// arrangement, and for its reasons. The alternative on macOS is a Mach service, which needs a
/// `MachServices` key in a launchd plist; toe is frequently started by `open Toe.app`, which
/// never goes through launchd at all, so that channel would exist for some launches and not
/// others. A socket in the state directory works however toe was started.
///
/// The request half is shaped as a struct with an `op` rather than as an enum with associated
/// values, so that the JSON on the wire reads the way a person would write it by hand —
/// `{"op":"query","what":"windows"}` — and so a field added later is absent rather than
/// breaking a client that predates it. The response half is the part a language model reads,
/// and it is the half that is shaped for a reader.
public struct ControlRequest: Codable, Equatable, Sendable {

    /// Bumped when the meaning of a field changes rather than when one is added. The server
    /// refuses a request from a future protocol rather than guessing at it — one binary is
    /// both halves, so a mismatch means the app was replaced under a shell that still has the
    /// old one on its PATH, and saying so beats acting on half-understood JSON.
    public static let currentVersion = 1

    public enum Op: String, Codable, Sendable {
        case query
        case dispatch
        case focus
        case layoutSave
        case layoutApply
        case layoutList
        case layoutShow
        case layoutDelete
    }

    public var version: Int
    public var op: Op
    /// What to report, for `query`; the profile's name, for the `layout` operations.
    public var what: String?
    /// The command lines for `dispatch`, in the order they should run. More than one is
    /// deliberate: a batch renders once at the end, which is the difference between a layout
    /// arriving and a layout being assembled in front of you.
    public var commands: [String]?
    /// A window selector — the window `focus` acts on, or the one `dispatch` acts on instead
    /// of whichever window happens to hold the focus.
    public var window: String?

    public init(op: Op, what: String? = nil, commands: [String]? = nil, window: String? = nil) {
        self.version = Self.currentVersion
        self.op = op
        self.what = what
        self.commands = commands
        self.window = window
    }
}

/// What `query` can be asked for.
public enum ControlQuery: String, Codable, CaseIterable, Sendable {
    case state
    case windows
    case workspaces
    case monitors
    case binds
    case commands
    case layouts
    case skill
}

// MARK: - What a query answers with

/// One window, as everything outside toe sees it.
///
/// The frame is the layout's, not Accessibility's. Asking the system where each window is
/// would be one synchronous round trip per window on the main thread — `isManageable` alone is
/// six per candidate — and it would answer for a window on a hidden workspace with the stash
/// corner, which is where toe parked it rather than where it belongs. The frame toe intends is
/// the true answer to "where is this window", and it costs nothing.
public struct WindowReport: Codable, Equatable, Sendable {
    public var id: WindowID
    /// The application's own name — "Ghostty", "Safari". What a person, or a model, calls it.
    public var app: String
    /// The bundle identifier, which is what `[[float]]` rules match on and the stabler of the
    /// two names. Absent for the occasional process that has none.
    public var bundle: String?
    public var title: String?
    public var workspace: Int?
    public var monitor: UInt32?
    /// Where the layout puts it, or nil while its workspace is hidden — see the note above.
    public var frame: Box?
    public var floating: Bool
    public var focused: Bool
    /// On a workspace that is not currently showing. Not a macOS Space: the window is parked
    /// off-screen and is still in Cmd-Tab, which is a thing worth knowing before concluding
    /// that a command did nothing.
    public var hidden: Bool

    public init(id: WindowID, app: String, bundle: String? = nil, title: String? = nil,
                workspace: Int? = nil, monitor: UInt32? = nil, frame: Box? = nil,
                floating: Bool = false, focused: Bool = false, hidden: Bool = false) {
        self.id = id
        self.app = app
        self.bundle = bundle
        self.title = title
        self.workspace = workspace
        self.monitor = monitor
        self.frame = frame
        self.floating = floating
        self.focused = focused
        self.hidden = hidden
    }
}

public struct WorkspaceReport: Codable, Equatable, Sendable {
    public var index: Int
    public var monitor: UInt32
    public var visible: Bool
    public var focused: Bool
    /// Tiles first, in the order they sit in the tree from left to right, then the detached
    /// windows. That order is the one a layout profile replays, so it is the order this reports.
    public var windows: [WindowID]

    public init(index: Int, monitor: UInt32, visible: Bool, focused: Bool, windows: [WindowID]) {
        self.index = index
        self.monitor = monitor
        self.visible = visible
        self.focused = focused
        self.windows = windows
    }
}

public struct MonitorReport: Codable, Equatable, Sendable {
    public var id: UInt32
    /// The durable key the session file uses, which survives a replug where the id does not.
    public var key: String?
    public var name: String?
    public var frame: Box
    /// The tiling area: the frame with the menu bar, the Dock and anything else that reserves
    /// space already taken out.
    public var usable: Box
    public var workspace: Int?
    public var focused: Bool

    public init(id: UInt32, key: String? = nil, name: String? = nil, frame: Box, usable: Box,
                workspace: Int? = nil, focused: Bool = false) {
        self.id = id
        self.key = key
        self.name = name
        self.frame = frame
        self.usable = usable
        self.workspace = workspace
        self.focused = focused
    }
}

/// Everything at once — the shape a model should ask for first, because the three lists only
/// mean anything against each other.
public struct StateReport: Codable, Equatable, Sendable {
    public var version: String?
    public var focusedWindow: WindowID?
    public var focusedWorkspace: Int
    public var focusedMonitor: UInt32
    public var monitors: [MonitorReport]
    public var workspaces: [WorkspaceReport]
    public var windows: [WindowReport]

    public init(version: String? = nil, focusedWindow: WindowID? = nil, focusedWorkspace: Int,
                focusedMonitor: UInt32, monitors: [MonitorReport],
                workspaces: [WorkspaceReport], windows: [WindowReport]) {
        self.version = version
        self.focusedWindow = focusedWindow
        self.focusedWorkspace = focusedWorkspace
        self.focusedMonitor = focusedMonitor
        self.monitors = monitors
        self.workspaces = workspaces
        self.windows = windows
    }
}

/// One live binding. The key and what it does, in the words the keybindings page uses.
///
/// No command string. Spelling a `Command` back out would be a fifth exhaustive switch over it
/// — `CommandParser`, `Coordinator.dispatch`, `CommandLabel` and `MenuModel.rank` are the four
/// — and the vocabulary a caller actually needs is `query commands`, which is a table rather
/// than a transcription and cannot drift out of step without a test noticing.
public struct BindReport: Codable, Equatable, Sendable {
    public var keys: String
    public var does: String

    public init(keys: String, does: String) {
        self.keys = keys
        self.does = does
    }
}

/// What ran, and what it did. `dispatch`'s answer.
public struct DispatchReport: Codable, Equatable, Sendable {
    /// The command lines, as they were parsed and accepted.
    public var ran: [String]
    /// The window they acted on, when `--window` named one.
    public var window: WindowID?

    public init(ran: [String], window: WindowID? = nil) {
        self.ran = ran
        self.window = window
    }
}

/// Where the skill file is and whether what is there is what this copy of toe would write.
public struct SkillReport: Codable, Equatable, Sendable {
    public var path: String
    public var installed: Bool
    /// Installed, but written by a different copy of toe — most often the development build,
    /// since the document names the binary that wrote it.
    public var stale: Bool

    public init(path: String, installed: Bool, stale: Bool) {
        self.path = path
        self.installed = installed
        self.stale = stale
    }
}

// MARK: - The envelope

/// A reply that worked. `ok` is a constant so that a reader — a person at a terminal or a model
/// reading stdout — can tell the two apart without knowing which query it was.
public struct ControlSuccess<Result: Encodable>: Encodable {
    public let ok = true
    public let result: Result

    public init(_ result: Result) { self.result = result }
}

/// A refusal, with the sentence the caller should be shown.
///
/// Its own type rather than `String` because a `Result` wants an `Error`, and rather than an
/// enum of cases because there is nothing to switch on: every one of these ends up printed on
/// somebody's terminal or read by a model, and the useful distinction between them is the words.
public struct Refusal: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public struct ControlFailure: Codable, Equatable, Sendable {
    public let ok: Bool
    public let error: String

    public init(_ error: String) {
        self.ok = false
        self.error = error
    }
}

public enum ControlCoding {

    /// Pretty-printed and sorted.
    ///
    /// Sorted because the alternative is not "declaration order" but *no* order: Foundation
    /// encodes through an unordered dictionary, so without this the fields of a window come out
    /// in whatever sequence the hashing produced that run. Declaration order would read better —
    /// `id`, `app`, `title` is how a person reads a window — but it is not on offer, and a
    /// profile on disk that reorders itself between two writes, or a reply a script cannot diff
    /// against yesterday's, is a worse thing to be than alphabetical.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The whole reply as one line, newline-terminated. Newline-framed rather than
    /// length-prefixed because the far end is as likely to be `nc` as it is to be toe.
    public static func line<T: Encodable>(_ value: T) -> Data {
        let encoder = encoder()
        // Pretty printing puts newlines *inside* the payload, so the framing newline cannot be
        // a delimiter for the response the way it is for the request. It does not need to be:
        // the server closes its side when it is done, and the client reads to end of file.
        var data = (try? encoder.encode(value)) ?? Data(#"{"ok":false,"error":"could not encode the reply"}"#.utf8)
        data.append(0x0a)
        return data
    }
}
