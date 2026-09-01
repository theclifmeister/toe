import Foundation

/// One row of the quick menu.
///
/// Deliberately AppKit-free: an icon is *named*, not drawn, and an action is *described*, not
/// closed over. That is what lets the whole tree be a value the selftest can assert against, and
/// it keeps every side effect in `Sources/toe` where it belongs.
public struct MenuEntry: Equatable {

    public enum Kind: Equatable {
        case action(MenuAction)
        /// Recurses through `Array`, so no `indirect` is needed and `Equatable` synthesises.
        case submenu([MenuEntry])
        /// A label you cannot select: "No windows", the version row.
        case info
    }

    /// Stable and hierarchical — `"windows"`, `"windows.4271"`, `"style.theme.nord"`. Tests
    /// assert against these rather than against titles, which are free to be reworded.
    public let id: String
    public let title: String
    /// Right-aligned hint: a shortcut, a window count, a workspace number, "empty".
    public let detail: String?
    public let icon: MenuIcon?
    /// Matchable but never displayed — "browser" finds Safari.
    public let keywords: [String]
    public let kind: Kind
    public var isEnabled: Bool
    /// A checkmark: the current workspace, the active theme.
    public var isOn: Bool

    public init(id: String,
                title: String,
                detail: String? = nil,
                icon: MenuIcon? = nil,
                keywords: [String] = [],
                kind: Kind,
                isEnabled: Bool = true,
                isOn: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
        self.keywords = keywords
        self.kind = kind
        self.isEnabled = isEnabled
        self.isOn = isOn
    }

    public var isSubmenu: Bool { if case .submenu = kind { return true }; return false }
    public var isSelectable: Bool {
        guard isEnabled else { return false }
        if case .info = kind { return false }
        return true
    }
    public var children: [MenuEntry] {
        if case .submenu(let items) = kind { return items }
        return []
    }

    // Small conveniences, so MenuTree reads as a list of rows rather than a wall of initialisers.
    /// No `detail` by default: a row that drills down already says so with its chevron, and a bare
    /// count beside every top-level row is noise Omarchy's own menu does without. An empty submenu
    /// is disabled rather than a dead end you can walk into.
    public static func submenu(_ id: String, _ title: String, icon: MenuIcon? = nil,
                               keywords: [String] = [], _ items: [MenuEntry]) -> MenuEntry {
        MenuEntry(id: id, title: title, detail: nil,
                  icon: icon, keywords: keywords, kind: .submenu(items),
                  isEnabled: !items.isEmpty)
    }

    public static func action(_ id: String, _ title: String, _ action: MenuAction,
                              detail: String? = nil, icon: MenuIcon? = nil,
                              keywords: [String] = [], isEnabled: Bool = true,
                              isOn: Bool = false) -> MenuEntry {
        MenuEntry(id: id, title: title, detail: detail, icon: icon, keywords: keywords,
                  kind: .action(action), isEnabled: isEnabled, isOn: isOn)
    }

    public static func info(_ id: String, _ title: String, detail: String? = nil,
                            icon: MenuIcon? = nil) -> MenuEntry {
        MenuEntry(id: id, title: title, detail: detail, icon: icon, kind: .info, isEnabled: false)
    }
}

/// Semantic, so ToeCore names an icon and `Sources/toe` decides how to draw it.
///
/// SF Symbols rather than Omarchy's Nerd Font glyphs, and on purpose: `StatusItem.marker` draws
/// its workspace square rather than setting a glyph precisely so toe needs no font installed, and
/// shipping glyphs here would be tofu on a stock Mac. The nerd-font name each symbol stands in for
/// is recorded beside it in `MenuIcon.Section.symbolName`.
public enum MenuIcon: Equatable {
    case section(Section)
    /// Reuses the marker `StatusItem` already draws for the menu bar strip.
    case workspace(index: Int, filled: Bool)
    /// `NSRunningApplication(processIdentifier:)?.icon`
    case runningApp(pid: Int32)
    /// A theme swatch, drawn with the same gradient as the focus border.
    case gradient(start: String, end: String)
    /// An SF Symbol name, for one-offs.
    case symbol(String)

    public enum Section: String, Equatable, CaseIterable {
        case apps, windows, workspaces, layout, style, setup, system, about

        /// The SF Symbol, and the Omarchy glyph it stands in for.
        public var symbolName: String {
            switch self {
            case .apps:       return "square.grid.2x2"          // nf-md-apps
            case .windows:    return "macwindow.on.rectangle"   // nf-md-window_restore
            case .workspaces: return "rectangle.3.group"        // nf-md-view_dashboard
            case .layout:     return "rectangle.split.2x1"      // nf-md-view_split_vertical
            case .style:      return "paintpalette"             // nf-md-palette
            case .setup:      return "slider.horizontal.3"      // nf-md-tune
            case .system:     return "power"                    // nf-md-power
            case .about:      return "info.circle"              // nf-md-information_outline
            }
        }
    }
}
