import ToeCore

/// Everything a bar panel needs for one frame: the items, the sizes, the colours.
///
/// Assembled by the Coordinator on every `refreshStatus` and handed to every panel, which lays
/// it out for its own width. A value rather than the Coordinator's state, for the reason
/// `MenuSnapshot` is one: the view gets a copy it cannot mutate into a second, divergent bar.
struct BarSnapshot: Equatable {
    var items: [BarItem]
    var metrics: BarMetrics
    var background: RGBA
    var foreground: RGBA
    var active: RGBA
    /// Width of the T mark, in points, which the view draws in place of a label for `.menu` —
    /// `BarItems.menu(markWidth:)` sized its slot from the same number.
    var markWidth: Double
    var markHeight: Double
}
