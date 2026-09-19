import Foundation

/// What each widget on the right of the bar shows for a given state — the glyph rules out of
/// Omarchy's panel models, as functions of the numbers a Mac reports.
///
/// The providers in `toe` read the system and hand the numbers here; nothing in this file knows
/// where a battery fraction comes from, which is what keeps every rule in the selftest. The
/// thresholds are upstream's own, cited on each.
public enum BarWidgets {

    /// `panels/power/Model.js`, `batteryIcon`: ten steps by `floor(fraction × 10)`, capped at
    /// 9; the charging set while the power is on; the full glyph once charged. `charging`
    /// false on mains is upstream's charge-threshold case — a battery held at 80% by the
    /// system's own optimisation — and draws the plain set, since nothing is flowing in.
    ///
    /// With `showPercentage` the label leads with the number and the slot doubles, as
    /// `slotSize: Style.bar.iconSlot * 2` does upstream.
    public static func power(fraction: Double, onMains: Bool, charging: Bool, charged: Bool,
                             showPercentage: Bool, metrics: BarMetrics) -> BarItem {
        let clamped = max(0, min(1, fraction))
        let glyph = batteryGlyph(fraction: clamped, onMains: onMains, charging: charging, charged: charged)
        let percent = Int((clamped * 100).rounded())
        let tooltip = onMains ? "\(percent)%, on power" : "\(percent)%, on battery"
        return BarItems.icon(.power, glyph: showPercentage ? "\(percent)% \(glyph)" : glyph,
                             tooltip: tooltip, slots: showPercentage ? 2 : 1, metrics: metrics)
    }

    /// The glyph alone — the bar's widget and the power panel's hero draw the same one, so
    /// the rule is in one place.
    public static func batteryGlyph(fraction: Double, onMains: Bool, charging: Bool, charged: Bool) -> String {
        let clamped = max(0, min(1, fraction))
        let index = max(0, min(9, Int((clamped * 10).rounded(.down))))
        if charged { return Glyphs.batteryFull }
        if onMains && charging { return Glyphs.charging[index] }
        return Glyphs.battery[index]
    }

    /// `panels/audio/Panel.qml`, `outputIcon`: headphones before anything, then muted, then
    /// the three levels at 0.34 and 0.67, and the muted glyph again for a volume of nothing —
    /// "the old Waybar pulseaudio glyph set".
    public static func audio(volume: Double, muted: Bool, headphones: Bool,
                             metrics: BarMetrics) -> BarItem {
        let glyph: String
        if headphones {
            glyph = Glyphs.headphones
        } else if muted || volume <= 0 {
            glyph = Glyphs.muted
        } else if volume >= 0.67 {
            glyph = Glyphs.volume[2]
        } else if volume >= 0.34 {
            glyph = Glyphs.volume[1]
        } else {
            glyph = Glyphs.volume[0]
        }
        let percent = Int((max(0, min(1, volume)) * 100).rounded())
        return BarItems.icon(.audio, glyph: glyph,
                             tooltip: muted ? "Muted" : "Volume \(percent)%", metrics: metrics)
    }

    /// How the machine is on the network, as `panels/network/Model.js` tells them apart.
    public enum Connection: Equatable, Sendable {
        /// `strength` 0–100, the shape `nmcli` reports it in; `restricted` is a captive portal
        /// or otherwise limited link, drawn in `active`.
        case wifi(strength: Int, restricted: Bool)
        case ethernet(restricted: Bool)
        case none
    }

    /// `connectionIcon` and `wifiIconFor`: five signal glyphs by `ceil(strength / 20) − 1`,
    /// the restricted glyphs in `active`, the wired glyph, and the crossed-out one for no
    /// connection at all.
    public static func network(_ connection: Connection, metrics: BarMetrics) -> BarItem {
        let glyph = networkGlyph(connection)
        switch connection {
        case .wifi(let strength, let restricted):
            return BarItems.icon(.network, glyph: glyph, active: restricted,
                                 tooltip: restricted ? "Wi-Fi, limited" : "Wi-Fi, \(strength)%",
                                 metrics: metrics)
        case .ethernet(let restricted):
            return BarItems.icon(.network, glyph: glyph, active: restricted,
                                 tooltip: restricted ? "Wired, limited" : "Wired", metrics: metrics)
        case .none:
            return BarItems.icon(.network, glyph: glyph, tooltip: "No network", metrics: metrics)
        }
    }

    /// The glyph alone, for the network panel's hero as well as the widget.
    public static func networkGlyph(_ connection: Connection) -> String {
        switch connection {
        case .wifi(let strength, let restricted):
            let index = max(0, min(4, Int((Double(strength) / 20).rounded(.up)) - 1))
            return restricted ? Glyphs.wifiRestricted : Glyphs.wifi[index]
        case .ethernet(let restricted):
            return restricted ? Glyphs.ethernetRestricted : Glyphs.ethernet
        case .none:
            return Glyphs.disconnected
        }
    }

    /// Wi-Fi signal as a percentage from the RSSI CoreWLAN reports, the way NetworkManager
    /// derives `nmcli`'s strength: linear from −100 dBm (nothing) to −50 dBm (full), clamped.
    /// So −47 is 100, −75 is 50 and −90 is 20 — the fifth, third and first glyph.
    public static func wifiStrength(rssi: Int) -> Int {
        max(0, min(100, 2 * (rssi + 100)))
    }

    /// `panels/bluetooth/Panel.qml`, `icon`: off, on, and on with something connected.
    public static func bluetooth(on: Bool, connected: Int, metrics: BarMetrics) -> BarItem {
        let glyph = !on ? Glyphs.bluetoothOff : (connected > 0 ? Glyphs.bluetoothConnected : Glyphs.bluetoothOn)
        let tooltip = !on ? "Bluetooth off"
            : (connected == 0 ? "Bluetooth on" : "Bluetooth, \(connected) connected")
        return BarItems.icon(.bluetooth, glyph: glyph, tooltip: tooltip, metrics: metrics)
    }

    /// `panels/monitor/Panel.qml`: one glyph for one display, another for more.
    public static func monitor(count: Int, metrics: BarMetrics) -> BarItem {
        BarItems.icon(.monitor, glyph: count > 1 ? Glyphs.monitors : Glyphs.monitor,
                      tooltip: count == 1 ? "1 display" : "\(count) displays", metrics: metrics)
    }

    /// `KeyboardLayoutModel.shortLabel`: the first three letters of the layout's brief name,
    /// upper-cased — `EN`, `DE`, `ABC`. Empty for an empty name.
    public static func keyboardLabel(_ brief: String) -> String {
        let word = brief.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).first.map(String.init) ?? ""
        return String(word.prefix(3)).uppercased()
    }
}
