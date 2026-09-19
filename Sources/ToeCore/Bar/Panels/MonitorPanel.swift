import Foundation

/// The monitor panel — `panels/monitor/Panel.qml`, cut to what a Mac lets a process see.
///
/// Upstream is a brightness slider, a text-size slider, a row of scale presets and a list of
/// displays that can be switched off. None of the four has a public route on macOS: brightness
/// is `DisplayServices`, private (measured on this machine for #177 — no `IODisplayConnect`
/// service exists on Apple silicon, so the one public call, `IODisplayGetFloatParameter`,
/// has nothing to ask; what the `IOMobileFramebuffer` entry carries is an undocumented number
/// with no public write); scale and text size are System Settings' by design; and a display
/// cannot be disabled through CoreGraphics. So this panel is the list of displays, which the
/// widget already counts, with what each one is, and the door to the Displays pane where the
/// four controls live. A row is told rather than pressed: `PanelRow.pick` with no action is a
/// row the cursor steps over, drawn with the selected fill for the display the focus is on.
public enum MonitorPanel {

    /// One display, as `NSScreen` and `CGDisplayCopyDisplayMode` describe it.
    public struct Display: Equatable, Sendable {
        public var id: UInt32
        /// `NSScreen.localizedName`: "Built-in Retina Display", "LG UltraFine".
        public var name: String
        /// In points, as the tiles are laid out.
        public var width: Double
        public var height: Double
        /// `backingScaleFactor`: 2 on a Retina display, 1 on the rest.
        public var scale: Double
        /// `CGDisplayMode.refreshRate`, or 0 where the display does not say — a ProMotion
        /// panel reports 120 and a plain one 60; some externals report nothing.
        public var refreshRate: Double
        public var builtin: Bool
        /// Where the focused window is, `WorkspaceManager.focusedMonitorID`.
        public var focused: Bool

        public init(id: UInt32, name: String, width: Double, height: Double, scale: Double = 1,
                    refreshRate: Double = 0, builtin: Bool = false, focused: Bool = false) {
            self.id = id
            self.name = name
            self.width = width
            self.height = height
            self.scale = scale
            self.refreshRate = refreshRate
            self.builtin = builtin
            self.focused = focused
        }
    }

    /// "1728 × 1117 at 2×, 120 Hz" — the points the layout works in, the scale and the rate,
    /// which together are what a person means by "which mode is it in". No refresh rate, no
    /// clause; a scale of 1 is not worth a clause either.
    public static func detail(_ d: Display) -> String {
        var text = "\(Int(d.width)) × \(Int(d.height))"
        if d.scale != 1 { text += " at \(formatted(d.scale))×" }
        if d.refreshRate > 0 { text += ", \(formatted(d.refreshRate)) Hz" }
        return text
    }

    /// A number without a trailing `.0`, and with its fraction when it has one — `2`, `1.5`,
    /// `59.94`.
    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
    }

    public static func rows(_ displays: [Display]) -> [PanelRow] {
        let count = displays.count
        var rows: [PanelRow] = [
            .hero(glyph: count > 1 ? Glyphs.monitors : Glyphs.monitor, title: "Display",
                  status: count == 1 ? "1 display" : "\(count) displays"),
            .separator,
            .header("Displays"),
        ]
        rows += displays.map { d in
            .pick(glyph: Glyphs.monitor, label: d.focused ? "\(d.name) · focused" : d.name,
                  detail: detail(d), current: d.focused, action: .none)
        }
        rows += [.separator, .settings(.displays)]
        return rows
    }
}
