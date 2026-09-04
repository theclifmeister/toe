import Foundation

/// The menu bar's workspace strip, in Omarchy's waybar styling.
///
/// Omarchy's `hyprland/workspaces` module maps the focused workspace to a filled rounded
/// square (`nf-md-square_rounded`) and every other one to its own digit, with workspace 10
/// labelled `0` and empty workspaces at half opacity. This is the part of that with no
/// AppKit in it: which workspaces earn a slot, what each one is labelled, and how a click
/// lands on one. `StatusItem` draws the result.
public enum WorkspaceStrip {

    /// Omarchy's waybar declares `persistent-workspaces` 1-5, so the bar never has fewer
    /// than five slots on it — see `slots` for what that does and does not mean.
    public static let defaultPersistent = 5

    /// What the strip needs to know about one workspace.
    public struct State: Equatable {
        public let index: Int
        /// Showing on the monitor that currently has focus.
        public let isFocused: Bool
        /// Showing on some monitor — with several displays, more than one is visible.
        public let isVisible: Bool
        public let isEmpty: Bool

        public init(index: Int, isFocused: Bool, isVisible: Bool, isEmpty: Bool) {
            self.index = index
            self.isFocused = isFocused
            self.isVisible = isVisible
            self.isEmpty = isEmpty
        }
    }

    /// How a workspace is drawn. Omarchy separates only the focused one from the rest;
    /// `visible` is toe's addition, because Hyprland's bar leaves the second display
    /// unstyled and toe would rather not lose the signal.
    public enum Marker: Equatable {
        /// A filled rounded square, replacing the digit.
        case focused
        /// The same square, outlined.
        case visible
        /// The workspace's own digit.
        case digit
    }

    public struct Item: Equatable {
        public let index: Int
        /// What Omarchy labels the workspace: its digit, and `0` for workspace 10.
        public let label: String
        public let marker: Marker
        /// Omarchy's `#workspaces button.empty { opacity: 0.5 }`.
        public let dim: Bool
    }

    /// Which workspaces earn a slot, in the order they were given.
    ///
    /// A workspace earns one on merit by having windows on it or by being on screen right
    /// now. `persistent` — Omarchy's `persistent-workspaces` — is then a *floor on how many
    /// slots the strip has*, not a claim on the first five indices: only if fewer than
    /// `persistent` workspaces earned a slot is the strip padded out to that many, with the
    /// lowest empty ones. So a fresh session shows 1-5 and six workspaces in use show six,
    /// where taking `index <= persistent` literally used to wedge an empty 4 in between a
    /// busy 3 and 5 that had no need of the padding. Learned at v0.15.0.
    public static func slots(for states: [State],
                             persistent: Int = defaultPersistent) -> [Int] {
        let earned = states.filter { !$0.isEmpty || $0.isVisible }
        guard earned.count < persistent else { return earned.map(\.index) }

        // Pad in the order given — callers hand over 1-10 ascending, so this is Omarchy's
        // 1, 2, 3... and stops the moment the strip is `persistent` long.
        let padding = states.lazy
            .filter { $0.isEmpty && !$0.isVisible }
            .prefix(persistent - earned.count)
        let keep = Set(earned.map(\.index)).union(padding.map(\.index))
        return states.map(\.index).filter(keep.contains)
    }

    /// The strip itself: `slots`, each labelled and marked the way waybar does it.
    public static func items(for states: [State],
                             persistent: Int = defaultPersistent) -> [Item] {
        let keep = Set(slots(for: states, persistent: persistent))
        return states.filter { keep.contains($0.index) }.map { state in
            Item(index: state.index,
                 label: state.index == 10 ? "0" : "\(state.index)",
                 marker: state.isFocused ? .focused : (state.isVisible ? .visible : .digit),
                 dim: state.isEmpty)
        }
    }

    /// Which item a click at `x` landed on, as a position in `widths`.
    ///
    /// The strip is centred in `buttonWidth`, its items `gap` apart. Zones reach to the
    /// midpoint between neighbours so the gaps are not dead, but a click beyond either end
    /// of the strip returns nil — that is the padding, and nothing lives there.
    /// What a click landed on.
    public enum Hit: Equatable {
        /// toe's own mark, which leads the strip and opens the quick menu.
        case mark
        /// A workspace, by its position in `widths`.
        case workspace(Int)
    }

    /// `leading` is the mark's width plus the gap after it — part of what the strip is centred
    /// on, but not one of the `widths`, because it is not a workspace and does not take a
    /// workspace's share of a boundary between two of them.
    public static func hit(x: Double, widths: [Double], gap: Double, buttonWidth: Double,
                           leading: Double = 0) -> Hit? {
        guard !widths.isEmpty || leading > 0 else { return nil }

        let spans = widths.isEmpty ? 0 : gap * Double(widths.count - 1)
        let total = leading + widths.reduce(0, +) + spans
        let origin = (buttonWidth - total) / 2

        if leading > 0 {
            // The mark keeps its own space and the gap after it: a click in the gap is nearer
            // the mark than the first workspace, and the mark is the more forgiving target.
            guard x >= origin else { return nil }
            if x < origin + leading { return .mark }
        }
        guard !widths.isEmpty else { return nil }

        var starts: [Double] = []
        var cursor = origin + leading
        for width in widths {
            starts.append(cursor)
            cursor += width + gap
        }
        let ends = zip(starts, widths).map(+)

        guard x >= starts[0], x <= ends[ends.count - 1] else { return nil }

        for i in widths.indices {
            let left = i == 0 ? starts[0] : (ends[i - 1] + starts[i]) / 2
            let right = i == widths.count - 1 ? ends[i] : (ends[i] + starts[i + 1]) / 2
            if x >= left, x <= right { return .workspace(i) }
        }
        return nil
    }
}
