import Foundation

/// The menu bar's workspace strip, in Omarchy's waybar styling.
///
/// Omarchy's `hyprland/workspaces` module maps the focused workspace to a filled rounded
/// square (`nf-md-square_rounded`) and every other one to its own digit, with workspace 10
/// labelled `0` and empty workspaces at half opacity. This is the part of that with no
/// AppKit in it: which workspaces earn a slot, what each one is labelled, and how a click
/// lands on one. `StatusItem` draws the result.
public enum WorkspaceStrip {

    /// Omarchy's waybar declares `persistent-workspaces` 1-5, so those five keep a slot on
    /// the bar whether or not anything is on them.
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

    /// A workspace earns a slot by being one of the first `persistent` — Omarchy's
    /// `persistent-workspaces` — or by having windows on it, or by being on screen right
    /// now. So the first five are always there, and past those the strip stays as short as
    /// what you are actually using.
    public static func items(for states: [State],
                             persistent: Int = defaultPersistent) -> [Item] {
        states.filter { $0.index <= persistent || !$0.isEmpty || $0.isVisible }.map { state in
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
    public static func hit(x: Double, widths: [Double], gap: Double, buttonWidth: Double) -> Int? {
        guard !widths.isEmpty else { return nil }

        let total = widths.reduce(0, +) + gap * Double(widths.count - 1)
        let origin = (buttonWidth - total) / 2

        var starts: [Double] = []
        var cursor = origin
        for width in widths {
            starts.append(cursor)
            cursor += width + gap
        }
        let ends = zip(starts, widths).map(+)

        guard x >= starts[0], x <= ends[ends.count - 1] else { return nil }

        for i in widths.indices {
            let left = i == 0 ? starts[0] : (ends[i - 1] + starts[i]) / 2
            let right = i == widths.count - 1 ? ends[i] : (ends[i] + starts[i + 1]) / 2
            if x >= left, x <= right { return i }
        }
        return nil
    }
}
