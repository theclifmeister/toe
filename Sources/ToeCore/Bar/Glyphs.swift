import Foundation

/// Every Nerd Font codepoint the bar draws, in one table.
///
/// Each one is the literal out of the Omarchy widget it names — `shell/plugins/panels/*/Model.js`
/// and `shell/plugins/bar/indicators/*.qml` on `quattro` — read back as a codepoint rather than
/// pasted as a character, because a private-use glyph in a source file is invisible to a diff
/// and indistinguishable from the wrong one on a machine without the font. The bundled
/// JetBrainsMono Nerd Font covers all of them; `MenuFont`'s coverage check is what says so at
/// launch, and the selftest keeps this table's spelling honest.
///
/// One correction to the brief that named them: the focused workspace's rounded square is
/// `U+F14FB` (`nf-md-square_rounded`), which is what `"󱓻"` in `Workspaces.qml` decodes
/// to. `U+F0FB` is a Font Awesome glyph a good deal wider, and is not what Omarchy draws.
public enum Glyphs {

    // MARK: Workspaces

    /// `nf-md-square_rounded` — the focused workspace, in place of its digit.
    public static let workspace = "\u{F14FB}"

    // MARK: Indicators — `shell/plugins/bar/indicators/`

    /// `nf-md-bell_off`. Dnd: notifications are silenced — a Focus is on, on a Mac.
    public static let doNotDisturb = "\u{F009B}"

    // MARK: Bluetooth — `panels/bluetooth/Panel.qml`

    public static let bluetoothOff = "\u{F00B2}"
    public static let bluetoothOn = "\u{F00AF}"
    public static let bluetoothConnected = "\u{F00B1}"

    // MARK: Network — `panels/network/Model.js`

    /// The five signal strengths, weakest first: `wifiIconFor` picks by `ceil(strength / 20)`.
    public static let wifi = ["\u{F092F}", "\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"]
    /// Wi-Fi behind a captive portal or otherwise limited — drawn in `active`.
    public static let wifiRestricted = "\u{F0929}"
    public static let ethernet = "\u{F0200}"
    public static let ethernetRestricted = "\u{F0202}"
    /// `nf-md-wifi_strength_off_outline`: no connection at all.
    public static let disconnected = "\u{F092E}"

    // MARK: Audio — `panels/audio/Panel.qml`, "the old Waybar pulseaudio glyph set"

    /// The three volume levels, quietest first: `outputIcon` picks by 0.34 and 0.67.
    public static let volume = ["\u{F026}", "\u{F027}", "\u{F028}"]
    public static let muted = "\u{EEE8}"
    public static let headphones = "\u{F02CB}"

    // MARK: Monitor — `panels/monitor/Panel.qml`

    public static let monitor = "\u{F0379}"
    public static let monitors = "\u{F037A}"

    // MARK: Power — `panels/power/Model.js`

    /// Ten steps on battery, emptiest first: `batteryIcon` indexes by `floor(fraction * 10)`,
    /// capped at 9.
    public static let battery = ["\u{F007A}", "\u{F007B}", "\u{F007C}", "\u{F007D}", "\u{F007E}",
                                 "\u{F007F}", "\u{F0080}", "\u{F0081}", "\u{F0082}", "\u{F0079}"]
    /// The same ten steps with a bolt, for when the power is on.
    public static let charging = ["\u{F089C}", "\u{F0086}", "\u{F0087}", "\u{F0088}", "\u{F089D}",
                                  "\u{F0089}", "\u{F089E}", "\u{F008A}", "\u{F008B}", "\u{F0085}"]
    /// `nf-md-battery_charging_100`: full, and still plugged in.
    public static let batteryFull = "\u{F0085}"

    /// Every glyph above, flat, for a coverage check to walk — the font is asked once for the
    /// whole set at launch rather than per glyph at draw time. Spelled as one `joined()` over
    /// typed rows rather than a chain of `+`: the chain is fine on a current toolchain and
    /// "unable to type-check this expression in reasonable time" on the CI runner's.
    public static let all: [String] = {
        let rows: [[String]] = [
            [workspace, doNotDisturb, bluetoothOff, bluetoothOn, bluetoothConnected],
            wifi, [wifiRestricted, ethernet, ethernetRestricted, disconnected],
            volume, [muted, headphones, monitor, monitors],
            battery, charging, [batteryFull],
        ]
        return Array(rows.joined())
    }()
}
