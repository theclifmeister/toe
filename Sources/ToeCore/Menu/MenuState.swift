import Foundation

/// One visible row: an entry plus which of its title's characters the query matched.
public struct MenuRow: Equatable {
    public let entry: MenuEntry
    public let offsets: [Int]
    public init(entry: MenuEntry, offsets: [Int]) {
        self.entry = entry
        self.offsets = offsets
    }
}

/// What the host should do about a keystroke.
public enum MenuOutcome: Equatable {
    case ignored
    case redraw
    case dismiss
    /// A leaf action. `.submenu` is pushed internally and never surfaces here.
    case perform(MenuAction)
}

/// The whole quick menu interaction as a value: the level stack, the query, the selection and the
/// scroll window. Everything the panel draws comes from here, so the view holds no state of its own
/// and every rule below is assertable headlessly.
public struct MenuState {

    public struct Level: Equatable {
        public let title: String
        public let items: [MenuEntry]
        var query: String = ""
        var selection: Int = 0
        var scrollOffset: Int = 0
    }

    private var stack: [Level]
    public let wraps: Bool
    public var visibleRows: Int

    public init(root: MenuEntry, visibleRows: Int, wraps: Bool = true) {
        self.stack = [Level(title: root.title, items: root.children)]
        self.visibleRows = max(1, visibleRows)
        self.wraps = wraps
    }

    // MARK: - What the view reads

    public var query: String { stack[stack.count - 1].query }
    public var selection: Int { stack[stack.count - 1].selection }
    public var scrollOffset: Int { stack[stack.count - 1].scrollOffset }
    public var depth: Int { stack.count - 1 }
    public var breadcrumb: [String] { stack.map(\.title) }
    /// walker's `-p` prompt: the level you are in, with an ellipsis.
    public var prompt: String { "\(stack[stack.count - 1].title)…" }
    public var rows: [MenuRow] {
        FuzzyMatch.rank(stack[stack.count - 1].query, stack[stack.count - 1].items)
    }
    public var selectedRow: MenuRow? {
        let rows = self.rows
        guard rows.indices.contains(selection) else { return nil }
        return rows[selection]
    }

    /// Pushes a level built by the host — used for the `Confirm / Cancel` step, which needs to
    /// exist only for as long as the question is on screen.
    public mutating func push(title: String, items: [MenuEntry]) {
        stack.append(Level(title: title, items: items))
    }

    // MARK: - Key handling

    public mutating func handle(_ key: MenuKey) -> MenuOutcome {
        switch key {
        case .character(let c):
            stack[stack.count - 1].query.append(c)
            resetSelection()
            return .redraw

        case .backspace:
            if stack[stack.count - 1].query.isEmpty {
                // Nothing left to delete, so Backspace means "back" — except at the root, where
                // only Esc dismisses. Backspacing your way out of the menu entirely would be
                // surprising.
                return pop() ? .redraw : .ignored
            }
            stack[stack.count - 1].query.removeLast()
            resetSelection()
            return .redraw

        case .deleteWord:
            guard !stack[stack.count - 1].query.isEmpty else { return .ignored }
            var text = stack[stack.count - 1].query
            while let last = text.last, last == " " { text.removeLast() }
            while let last = text.last, last != " " { text.removeLast() }
            stack[stack.count - 1].query = text
            resetSelection()
            return .redraw

        case .clearLine:
            guard !stack[stack.count - 1].query.isEmpty else { return .ignored }
            stack[stack.count - 1].query = ""
            resetSelection()
            return .redraw

        case .up:      return move(by: -1)
        case .down:    return move(by: 1)
        case .pageUp:  return move(by: -visibleRows)
        case .pageDown: return move(by: visibleRows)

        case .home:
            guard !rows.isEmpty else { return .ignored }
            return select(0)

        case .end:
            guard !rows.isEmpty else { return .ignored }
            return select(rows.count - 1)

        case .enter, .tab:
            guard let row = selectedRow, row.entry.isSelectable else { return .ignored }
            switch row.entry.kind {
            case .submenu(let items):
                stack.append(Level(title: row.entry.title, items: items))
                return .redraw
            case .action(let action):
                // Tab is descend-only: it should never fire an action by accident while
                // someone is reaching for it as a navigation key.
                guard key == .enter else { return .ignored }
                return .perform(action)
            case .info:
                return .ignored
            }

        case .escape:
            return pop() ? .redraw : .dismiss
        }
    }

    // MARK: - Selection and scrolling

    private mutating func resetSelection() {
        stack[stack.count - 1].selection = 0
        stack[stack.count - 1].scrollOffset = 0
    }

    private mutating func move(by delta: Int) -> MenuOutcome {
        let count = rows.count
        guard count > 0 else { return .ignored }
        var next = selection + delta
        if wraps, abs(delta) == 1 {
            next = (next + count) % count
        } else {
            next = min(max(next, 0), count - 1)
        }
        return select(next)
    }

    private mutating func select(_ index: Int) -> MenuOutcome {
        let count = rows.count
        guard count > 0 else { return .ignored }
        let clamped = min(max(index, 0), count - 1)
        stack[stack.count - 1].selection = clamped
        stack[stack.count - 1].scrollOffset = clampedScroll(for: clamped, count: count)
        return .redraw
    }

    /// Keeps the selection inside the visible window, scrolling by the minimum needed — so paging
    /// down through a long list moves one row at a time at the bottom edge rather than jumping.
    private func clampedScroll(for selection: Int, count: Int) -> Int {
        var offset = scrollOffset
        if selection < offset { offset = selection }
        if selection >= offset + visibleRows { offset = selection - visibleRows + 1 }
        let maxOffset = max(0, count - visibleRows)
        return min(max(0, offset), maxOffset)
    }

    /// Leaves the level you were in behind entirely, query and all: coming back to a level with
    /// your old filter still applied would be a small mystery every time.
    private mutating func pop() -> Bool {
        guard stack.count > 1 else { return false }
        stack.removeLast()
        return true
    }
}
