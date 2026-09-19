import Foundation

/// The power panel — `panels/power/Panel.qml`, cut to what a Mac says about its battery.
///
/// Upstream is a hero, a battery bar, a two-by-two of stats and a row of power profiles. The
/// profiles are gone: a Mac has Low Power Mode, and switching it is `pmset`, which is root's.
/// It is reported instead, beside the power source, in the stats. The rotating phrases
/// ("Pumping power", "Hoarding joules") are gone too — they are a timer for a joke, and the
/// status line says what `modeLabel` says when the joke is not playing.
public enum PowerPanel {

    /// What `PowerProvider` reads — the four numbers the bar's glyph already needed, and the
    /// four the panel adds. In ToeCore so the provider's state and the panel's input are one
    /// type, the way `BarWidgets.Connection` is for the network.
    public struct Battery: Equatable, Sendable {
        public var fraction: Double
        public var onMains: Bool
        public var charging: Bool
        public var charged: Bool
        /// `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullChargeKey`, in minutes; nil while the
        /// system is still working it out, which it is for a minute after every plug or
        /// unplug.
        public var minutesToEmpty: Int?
        public var minutesToFull: Int?
        /// `kIOPSBatteryHealthKey`: "Good", "Fair", "Poor" — or nil on a Mac that will not say.
        public var health: String?
        /// From the `AppleSmartBattery` registry entry, which every Mac with a battery has.
        public var cycleCount: Int?
        /// `AppleRawMaxCapacity` over `DesignCapacity`, as a percentage — the number System
        /// Settings calls Maximum Capacity.
        public var maximumCapacity: Int?
        public var lowPowerMode: Bool

        public init(fraction: Double, onMains: Bool, charging: Bool, charged: Bool,
                    minutesToEmpty: Int? = nil, minutesToFull: Int? = nil, health: String? = nil,
                    cycleCount: Int? = nil, maximumCapacity: Int? = nil, lowPowerMode: Bool = false) {
            self.fraction = fraction
            self.onMains = onMains
            self.charging = charging
            self.charged = charged
            self.minutesToEmpty = minutesToEmpty
            self.minutesToFull = minutesToFull
            self.health = health
            self.cycleCount = cycleCount
            self.maximumCapacity = maximumCapacity
            self.lowPowerMode = lowPowerMode
        }
    }

    /// `modeLabel`, with the Mac's word for the case upstream calls "Threshold": on power and
    /// not charging is Optimized Battery Charging holding the battery at 80%, and the battery
    /// menu says "Charging on hold" for it.
    public static func status(_ b: Battery) -> String {
        if b.charged || (b.onMains && b.fraction >= 1) { return "Fully charged" }
        if !b.onMains { return "On battery" }
        return b.charging ? "Charging" : "Charging on hold"
    }

    /// `h:mm`, as the battery menu prints a time; "Calculating…" while the system has no
    /// estimate yet, since it will have one in a minute and a blank reads as broken.
    public static func timeLabel(minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "Calculating…" }
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// System Settings' two words for `kIOPSBatteryHealthKey`'s three.
    public static func conditionLabel(_ health: String?) -> String {
        guard let health else { return "—" }
        return health == "Good" ? "Normal" : "Service recommended"
    }

    public static func rows(_ b: Battery) -> [PanelRow] {
        let percent = Int((max(0, min(1, b.fraction)) * 100).rounded())
        let idle = b.charged || (b.onMains && (!b.charging || b.fraction >= 1))
        // "Time left" on battery, "Time to full" on power, and a dash rather than a time when
        // nothing is flowing — held at 80% has no time to full.
        let time: PanelRow.Info
        if !b.onMains {
            time = PanelRow.Info("Time left", timeLabel(minutes: b.minutesToEmpty))
        } else if idle {
            time = PanelRow.Info("Time to full", "—")
        } else {
            time = PanelRow.Info("Time to full", timeLabel(minutes: b.minutesToFull))
        }
        return [
            .hero(glyph: BarWidgets.batteryGlyph(fraction: b.fraction, onMains: b.onMains,
                                                 charging: b.charging, charged: b.charged),
                  title: "Battery", status: status(b), trailing: .text("\(percent)%")),
            .progress(b.fraction),
            .info([time, PanelRow.Info("Condition", conditionLabel(b.health))]),
            .info([PanelRow.Info("Charge cycles", b.cycleCount.map(String.init) ?? "—"),
                   PanelRow.Info("Maximum capacity", b.maximumCapacity.map { "\($0)%" } ?? "—")]),
            .info([PanelRow.Info("Power source", b.onMains ? "Power adapter" : "Battery"),
                   PanelRow.Info("Low Power Mode", b.lowPowerMode ? "On" : "Off")]),
            .separator,
            .settings(.battery),
        ]
    }
}
