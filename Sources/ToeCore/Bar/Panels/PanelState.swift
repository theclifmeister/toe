import Foundation

/// What a keypress or click on a panel asks the app layer to do.
public enum PanelOutcome: Equatable {
    /// Nothing under the cursor, or a row that does nothing.
    case none
    case perform(PanelAction)
    /// Set this slider to this value — ←/→ on a slider row, or the wheel over one.
    case slide(PanelSlider, Double)
}

/// A panel without pixels: its rows, where the cursor is, and what a key does about it.
///
/// The same division `MenuState` makes for the quick menu, and not `MenuState` itself, though
/// #177 asked for that where it fits. It does not: `MenuState` is a tree of `MenuItem`s with a
/// fuzzy search across every level, and a panel is one flat list with no search, whose rows
/// are sliders, heroes and headers rather than titles. What carries across is the *rules* —
/// moves clamp rather than wrap, a row the cursor cannot rest on is stepped over in the
/// direction of travel and looked back for only when the list runs out that way, and a click
/// lands only on a row that would take the cursor. Those are upstream's `moveCursor` rules
/// too, section by section; here the sections are already flattened into the row list.
///
/// The cursor starts *hidden* — `selection` nil — as every upstream panel's `cursorActive`
/// starts false: a panel that opened with a row already lit would read as having chosen for
/// you. The first arrow reveals it on the first selectable row, and the pointer resting on a
/// row puts it there, which is what keeps keyboard and mouse to one highlight.
public struct PanelState: Equatable {

    /// `PanelSlider.step`: 5% a press, and the same per wheel notch as the bar itself.
    public static let sliderStep = 0.05

    public private(set) var rows: [PanelRow]
    public private(set) var selection: Int?

    public init(rows: [PanelRow]) {
        self.rows = rows
    }

    public var selectedRow: PanelRow? {
        guard let selection, rows.indices.contains(selection) else { return nil }
        return rows[selection]
    }

    // MARK: - Moving

    /// ↓ and ↑. With the cursor hidden the first press shows it at the near end of the list
    /// — ↓ on the first row you could choose, ↑ on the last — rather than moving from a row
    /// that was never lit.
    public mutating func move(by delta: Int) {
        guard delta != 0, rows.contains(where: \.isSelectable) else { return }
        guard let current = selection else {
            selection = delta > 0 ? selectable(from: 0, step: 1)
                                  : selectable(from: rows.count - 1, step: -1)
            return
        }
        let target = min(max(current + delta, 0), rows.count - 1)
        let step = delta > 0 ? 1 : -1
        if let landing = selectable(from: target, step: step) ?? selectable(from: target, step: -step) {
            selection = landing
        }
    }

    public mutating func moveToTop() {
        selection = selectable(from: 0, step: 1) ?? selection
    }

    public mutating func moveToEnd() {
        guard !rows.isEmpty else { return }
        selection = selectable(from: rows.count - 1, step: -1) ?? selection
    }

    /// The pointer over a row, or a press on one. A row the cursor could not rest on does not
    /// take it — the hover slides across a header the way the cursor steps over one.
    public mutating func select(row: Int) {
        guard rows.indices.contains(row), rows[row].isSelectable else { return }
        selection = row
    }

    // MARK: - Acting

    /// Return, Space, or a click on the selected row.
    public mutating func activate() -> PanelOutcome {
        guard let row = selectedRow, row.action != .none else { return .none }
        return .perform(row.action)
    }

    /// ←/→ on the cursor's row: a slider moves by `sliderStep`; anything else ignores them,
    /// as upstream's `adjustVolume` does when the cursor is on a device row rather than the
    /// slider — moving the global volume from a row that is not it would surprise.
    public mutating func adjust(by steps: Int) -> PanelOutcome {
        guard let selection else { return .none }
        return adjust(row: selection, by: steps)
    }

    /// The wheel over a slider row, which need not be the cursor's. The new value is written
    /// into the row at once so a run of notches steps from where the last one left it rather
    /// than from the value the provider has not yet confirmed; the provider's own answer
    /// arrives through `replace` and agrees, or corrects.
    public mutating func adjust(row: Int, by steps: Int) -> PanelOutcome {
        guard steps != 0, rows.indices.contains(row),
              case .slider(let which, let value, let dimmed) = rows[row].kind else { return .none }
        let next = max(0, min(1, value + Double(steps) * Self.sliderStep))
        guard next != value else { return .none }
        rows[row] = PanelRow(.slider(which, value: next, dimmed: dimmed), action: rows[row].action,
                             dimmed: rows[row].dimmed)
        return .slide(which, next)
    }

    /// A drag on a slider row: the value from the pointer's position, already clamped by
    /// `PanelLayout.sliderValue`. Same write-through as `adjust`.
    public mutating func set(row: Int, to value: Double) -> PanelOutcome {
        guard rows.indices.contains(row),
              case .slider(let which, let old, let dimmed) = rows[row].kind else { return .none }
        let next = max(0, min(1, value))
        guard next != old else { return .none }
        rows[row] = PanelRow(.slider(which, value: next, dimmed: dimmed), action: rows[row].action,
                             dimmed: rows[row].dimmed)
        return .slide(which, next)
    }

    // MARK: - The rows changing underneath

    /// New rows from the provider — a device appearing, the volume the keys just moved — with
    /// the cursor kept on the row it was on.
    ///
    /// By identity rather than index: a Bluetooth device that connects moves from the paired
    /// list to the connected one above it, and the row under the cursor would otherwise become
    /// the one that slid into its place. `PanelRow.identity` is what its action is about — the
    /// device it picks, the address it connects — or, for a slider and the hero, which one it
    /// is. A row that has gone (the device unpaired) leaves the cursor where the index was,
    /// clamped and stepped to something selectable, which is the trade `MenuState.rebuild`
    /// already makes.
    public mutating func replace(rows next: [PanelRow]) {
        let previous = selectedRow
        rows = next
        guard let selection, let previous else {
            self.selection = nil
            return
        }
        if let identity = previous.identity,
           let found = next.firstIndex(where: { $0.identity == identity }), next[found].isSelectable {
            self.selection = found
            return
        }
        let target = min(max(selection, 0), max(next.count - 1, 0))
        self.selection = selectable(from: target, step: 1) ?? selectable(from: target, step: -1)
    }

    // MARK: - Private

    /// The first selectable row at or beyond `start`, walking one way.
    private func selectable(from start: Int, step: Int) -> Int? {
        var index = start
        while rows.indices.contains(index) {
            if rows[index].isSelectable { return index }
            index += step
        }
        return nil
    }
}
