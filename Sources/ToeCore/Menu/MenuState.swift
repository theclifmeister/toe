import Foundation

/// What activating a row asks the app layer to do.
public enum MenuOutcome: Equatable {
    case pushed
    case popped
    case closed
    case run(Command)
    case toggleLoginItem
    case page(MenuPage)
    /// Nothing under the cursor — an empty list, filtered down to no rows at all.
    case none
}

/// The quick menu, entirely without pixels: what is on screen, what is selected, and what a
/// keypress does about it.
///
/// This is the same division `WorkspaceStrip` makes for the menu bar — everything decidable by
/// arithmetic lives here where `make test` can pin it, and `MenuView` is left with drawing.
public struct MenuState: Equatable {

    /// The levels descended into. Never empty: the last one is what `visible` filters.
    private var stack: [[MenuItem]]
    private var titles: [String]
    private var filtered: [MenuItem]

    public private(set) var query: String = ""
    public private(set) var selection: Int = 0
    public private(set) var scroll: Int = 0
    public private(set) var visibleRows: Int

    public init(root: [MenuItem], visibleRows: Int) {
        self.stack = [root]
        self.titles = []
        self.filtered = root
        self.visibleRows = max(1, visibleRows)
    }

    // MARK: - Reading

    public var visible: [MenuItem] { filtered }

    public var selectedItem: MenuItem? {
        filtered.indices.contains(selection) ? filtered[selection] : nil
    }

    /// The rows actually on screen.
    public var window: ArraySlice<MenuItem> {
        let end = min(filtered.count, scroll + visibleRows)
        guard scroll < end else { return [] }
        return filtered[scroll..<end]
    }

    public var breadcrumb: [String] { titles }

    /// walker's placeholder line: `Go…` at the root, the level's own name inside it.
    public var prompt: String { (titles.last ?? "Go") + "…" }


    public var isAtRoot: Bool { stack.count == 1 }

    // MARK: - Typing

    public mutating func type(_ text: String) {
        query += text
        refilter(resettingSelection: true)
    }

    /// False when there was nothing to delete, which is walker's cue to leave the submenu.
    @discardableResult
    public mutating func backspace() -> Bool {
        guard !query.isEmpty else { return false }
        query.removeLast()
        refilter(resettingSelection: true)
        return true
    }

    // MARK: - Moving

    /// Clamps rather than wraps. A menu of three rows could defensibly wrap; a keybindings list
    /// of fifty cannot — holding ↓ and finding yourself back at the top reads as a glitch.
    public mutating func move(by delta: Int) {
        guard !filtered.isEmpty else { return }
        selection = min(max(selection + delta, 0), filtered.count - 1)
        clampScroll()
    }

    public mutating func moveToTop() { selection = 0; clampScroll() }

    public mutating func moveToEnd() {
        selection = max(filtered.count - 1, 0)
        clampScroll()
    }

    /// A click, in on-screen rows rather than filtered indices.
    public mutating func select(row: Int) {
        let index = scroll + row
        guard filtered.indices.contains(index) else { return }
        selection = index
    }

    public mutating func setVisibleRows(_ rows: Int) {
        visibleRows = max(1, rows)
        clampScroll()
    }

    // MARK: - Acting

    public mutating func activate() -> MenuOutcome {
        guard let item = selectedItem else { return .none }
        switch item.action {
        case .submenu(let items):
            stack.append(items)
            titles.append(item.title)
            query = ""
            refilter(resettingSelection: true)
            return .pushed
        case .page(let page):
            return .page(page)
        case .run(let command):
            return .run(command)
        case .toggleLoginItem:
            return .toggleLoginItem
        case .note:
            // Pressing it does nothing, and `.none` is what the menu already does when there is
            // nothing to do — the panel stays open on the row you are looking at.
            return .none
        }
    }

    public mutating func pop() -> MenuOutcome {
        guard stack.count > 1 else { return .closed }
        stack.removeLast()
        if !titles.isEmpty { titles.removeLast() }
        query = ""
        refilter(resettingSelection: true)
        return .popped
    }

    /// Swaps the current level's rows without disturbing where the user is — what the login
    /// toggle needs, so the value flips under the cursor instead of the menu jumping.
    public mutating func replaceLevel(with items: [MenuItem]) {
        stack[stack.count - 1] = items
        refilter(resettingSelection: false)
    }

    /// Rebuilds every level from a fresh tree, leaving the user on the level and the row they
    /// were on.
    ///
    /// `replaceLevel` is not enough for a menu that changes while you are looking at it: the rows
    /// that move are two levels down from the root, and the caller would have to know which of
    /// `MenuModel`'s builders made the level in front of you in order to call the right one. So
    /// the whole tree is rebuilt and this walks back down it by title, which is a thing the state
    /// already records for the breadcrumb.
    ///
    /// A level that cannot be re-entered — its row is gone, or stopped leading anywhere — stops
    /// the walk and leaves you at the deepest level that still exists. That is a real case rather
    /// than a defensive one: `Background` appears only while the current theme has pictures, so
    /// changing to a theme with none takes the level you are standing in out from under you, and
    /// surfacing one rung up is the answer that cannot show rows belonging to a theme you left.
    public mutating func rebuild(root: [MenuItem]) {
        var levels: [[MenuItem]] = [root]
        var reached: [String] = []
        for title in titles {
            guard let item = levels[levels.count - 1].first(where: { $0.title == title }),
                  case .submenu(let children) = item.action else { break }
            levels.append(children)
            reached.append(title)
        }
        stack = levels
        titles = reached
        // The selection is kept rather than reset, which is what makes the fill appear under the
        // cursor instead of the list jumping to the top on every picture that lands. It is an
        // index into a list whose rows can move — a finished download leaves `available` for
        // `themes` — so `refilter` clamps it, and the row under the cursor afterwards may not be
        // the row that was under it before. That is the same trade `replaceLevel` already makes
        // for the startup toggle.
        refilter(resettingSelection: false)
    }

    // MARK: - Private

    /// Typing searches the whole tree below wherever you are, not the one level in front of you,
    /// and each hit carries the path it was found at — `Theme` under `Install › Style`. That is
    /// what Omarchy's menu does, and it is the difference between a filter and a search: you
    /// should not have to know that "Run on startup" lives under Configure in order to type it.
    ///
    /// An empty query is the plain level again, one rung at a time, with no paths to read.
    private mutating func refilter(resettingSelection: Bool) {
        let level = stack[stack.count - 1]
        if query.isEmpty {
            filtered = level
        } else {
            let flat = MenuState.flatten(level, path: [])
            // Both halves of a row are searchable. On the keybindings page the title is the
            // shortcut and the value is what it does, so a search that only read titles would
            // have you typing `SUPER` to find things.
            let fields = flat.map { [$0.item.title, $0.item.value ?? ""] }
            filtered = FuzzyFilter.rank(query, in: fields).map { match in
                let found = flat[match.index]
                return found.item.with(subtitle: found.path.isEmpty
                                       ? nil
                                       : found.path.joined(separator: " › "))
            }
        }
        if resettingSelection {
            // A keystroke re-ranks the list, so the old index refers to a row that has moved.
            selection = 0
            scroll = 0
        } else {
            selection = min(selection, max(filtered.count - 1, 0))
            clampScroll()
        }
    }

    /// Every row below this level, branches included: a branch is a thing you can go to, so it
    /// is a thing you can search for.
    private static func flatten(_ items: [MenuItem],
                                path: [String]) -> [(item: MenuItem, path: [String])] {
        var flat: [(item: MenuItem, path: [String])] = []
        for item in items {
            flat.append((item, path))
            if case .submenu(let children) = item.action {
                flat += flatten(children, path: path + [item.title])
            }
        }
        return flat
    }

    private mutating func clampScroll() {
        scroll = MenuLayout.scroll(offset: scroll, selection: selection,
                                   count: filtered.count, visibleRows: visibleRows)
    }
}
