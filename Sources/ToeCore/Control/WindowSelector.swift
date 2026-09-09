import Foundation

/// How something outside toe names a window it can see but cannot point at.
///
/// Every command toe has acts on the focused window, because every command toe has arrives on a
/// key and the key was pressed by somebody looking at the screen. A caller on the other end of a
/// socket is not looking at the screen: it has just read a list of windows and wants the third
/// one. So a selector is the missing half of the CLI, and it is deliberately the *only* new way
/// of naming a window — the commands themselves are unchanged.
///
/// The forms, in the order they are tried:
///
///     id:4213            exactly that window, and the only form that is not a guess
///     app:ghostty        the application's name or its bundle identifier, case-insensitive
///     bundle:com.apple   the bundle identifier alone
///     title:release      a case-insensitive substring of the title
///     workspace:3        every window on that workspace, which only `--window` narrows further
///     ghostty            no prefix: the application, then the title
///
/// A bare word tries the application first because that is what a caller means nine times in
/// ten, and because titles change under you — a browser's title is whatever page it is on, and
/// a selector that resolved yesterday resolves to nothing today. `app:` is the stable one and
/// the one the skill file tells a model to prefer.
public struct WindowSelector: Equatable, Sendable {

    public enum Field: String, Equatable, Sendable {
        case id
        case app
        case bundle
        case title
        case workspace
        /// No prefix: application, then title.
        case any
    }

    public let field: Field
    public let value: String

    public init(field: Field, value: String) {
        self.field = field
        self.value = value
    }

    /// Parses `app:Ghostty`. Never fails: an unknown prefix is not a prefix, it is part of the
    /// text being searched for — `Downloads:2024` is a window title before it is a mistake, and
    /// a selector that refused it would be wrong more often than it was helpful.
    public static func parse(_ raw: String) -> WindowSelector {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let colon = text.firstIndex(of: ":") else {
            return WindowSelector(field: .any, value: text)
        }
        let head = String(text[text.startIndex..<colon]).lowercased()
        let tail = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard let field = Field(rawValue: head), field != .any, !tail.isEmpty else {
            return WindowSelector(field: .any, value: text)
        }
        return WindowSelector(field: field, value: tail)
    }

    public func matches(_ window: WindowReport) -> Bool {
        switch field {
        case .id:
            // Exact, and by number: `id:0421` is not window 421, it is a typo.
            return UInt32(value).map { $0 == window.id } ?? false
        case .app:
            return contains(window.app) || equals(window.bundle)
        case .bundle:
            // Whole, like the bundle branch of `app:` above, and for the same reason — see
            // `equals`. This is the precise form of the two; somebody reaching for it is naming
            // one application exactly, not searching.
            return equals(window.bundle)
        case .title:
            return contains(window.title)
        case .workspace:
            return Int(value).map { $0 == window.workspace } ?? false
        case .any:
            return contains(window.app) || equals(window.bundle) || contains(window.title)
        }
    }

    private func contains(_ subject: String?) -> Bool {
        guard let subject else { return false }
        return subject.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Bundle identifiers are matched whole rather than by substring. `app:com.apple.Safari`
    /// naming Safari is right; `app:com` naming every Apple application at once is not, and a
    /// substring rule would do exactly that to the shortest and most tempting selectors. The
    /// substring rule is kept for the two fields where a fragment is what anybody means — an
    /// application's own name, and a window title.
    private func equals(_ subject: String?) -> Bool {
        guard let subject else { return false }
        return subject.compare(value, options: .caseInsensitive) == .orderedSame
    }
}

/// What resolving a selector against the live windows produced.
public enum SelectorResolution: Equatable {
    case one(WindowReport)
    /// More than one window answers to it. The caller is told which, rather than being given
    /// the first: acting on an arbitrary one of two terminals is the kind of help nobody asked
    /// for, and the list is exactly what a caller needs to write a narrower selector.
    case many([WindowReport])
    case none
}

public extension WindowSelector {

    /// Resolves against a window list, preferring exactness.
    ///
    /// The order matters more than it looks. A bare `Safari` matches an application named
    /// Safari and also every window whose title mentions it, and a caller that typed `Safari`
    /// meant the application — so a match on the application name wins outright, and the title
    /// matches are only consulted when nothing matched by application. Without that rule the
    /// most obvious selector anyone will ever type is ambiguous the moment a browser has a tab
    /// open about Safari.
    static func resolve(_ raw: String, in windows: [WindowReport]) -> SelectorResolution {
        let selector = parse(raw)
        let hits = windows.filter(selector.matches).sorted { $0.id < $1.id }
        guard selector.field == .any, hits.count > 1 else { return outcome(hits) }

        let byApp = hits.filter {
            WindowSelector(field: .app, value: selector.value).matches($0)
        }
        return outcome(byApp.isEmpty ? hits : byApp)
    }

    private static func outcome(_ hits: [WindowReport]) -> SelectorResolution {
        switch hits.count {
        case 0:  return .none
        case 1:  return .one(hits[0])
        default: return .many(hits)
        }
    }

    /// The sentence the caller gets back when a selector did not land on one window. Naming the
    /// candidates rather than the count, because the next thing the caller does is write a
    /// narrower selector and the ids are what it needs to do that.
    static func explain(_ resolution: SelectorResolution, selector raw: String) -> String? {
        switch resolution {
        case .one:
            return nil
        case .none:
            return "no window matches '\(raw)' — `toe query windows` lists what there is"
        case .many(let hits):
            let named = hits.prefix(8).map { window in
                "id:\(window.id) \(window.app)" + (window.title.map { " — \($0)" } ?? "")
            }
            let more = hits.count > 8 ? ", and \(hits.count - 8) more" : ""
            return "'\(raw)' matches \(hits.count) windows (\(named.joined(separator: "; "))\(more))"
                 + " — narrow it with id: or title:"
        }
    }
}
