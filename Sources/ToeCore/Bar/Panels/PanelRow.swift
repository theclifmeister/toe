import Foundation

/// Which panel — one per widget on the right of the bar, plus the clock's calendar. Omarchy's
/// `plugins/panels/*`, in its order.
public enum PanelKind: Equatable, Hashable, Sendable, CaseIterable {
    case bluetooth, network, audio, monitor, power, clock

    /// The widget the panel hangs from, and the one whose slot it is anchored under.
    public var widget: BarItem.Kind {
        switch self {
        case .bluetooth: return .bluetooth
        case .network:   return .network
        case .audio:     return .audio
        case .monitor:   return .monitor
        case .power:     return .power
        case .clock:     return .clock
        }
    }

    /// The panel a left click on `widget` opens, or nil for a widget that has none — the menu
    /// mark, the workspaces, the keyboard layout, which act rather than open.
    public init?(widget: BarItem.Kind) {
        guard let kind = PanelKind.allCases.first(where: { $0.widget == widget }) else { return nil }
        self = kind
    }
}

/// The System Settings pane a panel's last row opens. Symbolic, as `MenuItem.Icon` is: the
/// `x-apple.systempreferences:` identifier is the UI layer's to know (`SettingsPane` in `toe`),
/// and the selftest asserts `.sound` without a URL in sight.
public enum PanelSettings: Equatable, Sendable {
    case battery, displays, sound, wifi, bluetooth
}

/// A slider a panel carries, so that ←/→ and the wheel know which volume they are moving.
public enum PanelSlider: Equatable, Sendable {
    case outputVolume, inputVolume
}

/// What pressing a row asks the app layer to do. One enum across every panel rather than one
/// per panel, the way `Command` is one enum across every binding: the Coordinator switches on
/// it once, and a panel model is a pure function from what the machine reported to a list of
/// rows carrying these.
public enum PanelAction: Equatable, Sendable {
    /// A row that says something and does nothing — a header, a separator, the battery bar.
    case none
    case openSettings(PanelSettings)
    // Audio
    case toggleOutputMute
    case toggleInputMute
    /// By `AudioObjectID`, which is what CoreAudio takes to set a default device.
    case pickOutput(UInt32)
    case pickInput(UInt32)
    // Network
    case toggleWifi
    // Bluetooth — no power switch: setting the adapter's power is a private preference call.
    /// By address, the one name a device keeps across connects and disconnects.
    case connectBluetooth(String)
    case disconnectBluetooth(String)
    // Clock
    case stepMonth(Int)
    case toggleWeekStart
    case today
    /// The Calendar application — where a click on the clock went before it had a panel.
    case openCalendar

    /// What the action is *about*, so a row can be recognised after its action changed: a
    /// device that connects goes from `connectBluetooth` to `disconnectBluetooth` and is the
    /// same device, and the cursor on it should stay on it. See `PanelState.replace`.
    public var subject: String? {
        switch self {
        case .none:                          return nil
        case .openSettings(let pane):        return "settings:\(pane)"
        case .toggleOutputMute:              return "output:mute"
        case .toggleInputMute:               return "input:mute"
        case .pickOutput(let id):            return "output:\(id)"
        case .pickInput(let id):             return "input:\(id)"
        case .toggleWifi:                    return "wifi"
        case .connectBluetooth(let address), .disconnectBluetooth(let address):
            return "bluetooth:\(address)"
        case .stepMonth(let delta):          return "month:\(delta)"
        case .toggleWeekStart:               return "weekstart"
        case .today:                         return "today"
        case .openCalendar:                  return "calendar"
        }
    }
}

/// One row of a panel — the value `PanelView` draws and `PanelState` moves the cursor over.
///
/// The kinds are Omarchy's `Ui/Panel*.qml` pieces, cut down to what the six panels use:
/// `PanelHero`, `PanelSectionHeader`, `PanelSlider`, `PanelSeparator`, the power panel's
/// `InfoPair` and progress bar, and the `CursorSurface` rows every device list is made of. The
/// `action` row is toe's own — "Open Sound settings…" — where the Settings-pane click from
/// before the panels existed went, so nothing is lost.
///
/// A row is selectable when it has an action or a slider: the cursor steps over the rest, as
/// `MenuState` steps over a disabled row. That is one rule in one place (`isSelectable`) and
/// the reason the hero carries its toggle as part of the row — upstream's "header" virtual
/// section is the hero's switch being a cursor target, and here it is the hero row being one.
public struct PanelRow: Equatable, Sendable {

    /// What stands at the hero's trailing edge.
    public enum HeroTrailing: Equatable, Sendable {
        /// The power panel's big percentage, `Style.font.displayLarge`.
        case text(String)
        /// A `ToggleSwitch` — audio's mute, Bluetooth's and Wi-Fi's power.
        case toggle(on: Bool)
    }

    /// One cell of an `InfoPair` row: a dim label on the left, the value on the right.
    public struct Info: Equatable, Sendable {
        public let label: String
        public let value: String
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    public enum Kind: Equatable, Sendable {
        /// `PanelHero`: a display-size glyph, a bold title, a small-caps status line.
        case hero(glyph: String, title: String, status: String, trailing: HeroTrailing?)
        /// `PanelSectionHeader`, upper-cased by the view; `trailing` is the percentage the
        /// audio panel hangs on the right of its OUTPUT header.
        case header(String, trailing: String?)
        /// `PanelSlider`, 0…1. `dimmed` is muted: the track draws at half opacity.
        case slider(PanelSlider, value: Double, dimmed: Bool)
        /// The power panel's battery bar — a track filled to the fraction, nothing to press.
        case progress(Double)
        /// `InfoPair`s side by side, in as many equal columns as there are cells.
        case info([Info])
        /// A `CursorSurface` list row: a glyph, a label, an optional second line or trailing
        /// detail, and whether it is the one in effect — the default device, the connected
        /// network — which draws the selected fill.
        case pick(glyph: String, label: String, detail: String?, current: Bool)
        /// `PanelSeparator`: a hairline.
        case separator
        /// A row that leads somewhere — the Settings pane — drawn with a trailing `›` like a
        /// menu row that goes down a level.
        case action(String)
        /// A row that explains itself and does nothing: "Bluetooth access was denied".
        case note(String)
        /// The clock panel's month: weekday headings across the top, six weeks of seven days
        /// with the ISO week number down the side. Not a cursor target — the `W` heading is
        /// the week-start toggle, found by `PanelLayout.calendarHit`.
        case calendar(ClockPanel.Grid)
        /// The month and year under the grid, with a chevron at each end that steps it.
        case monthNav(String)
    }

    public let kind: Kind
    public let action: PanelAction
    /// Drawn at 0.45, like an indicator that is off: a display that cannot be switched off
    /// because it is the last one, a device that is busy connecting.
    public let dimmed: Bool

    public init(_ kind: Kind, action: PanelAction = .none, dimmed: Bool = false) {
        self.kind = kind
        self.action = action
        self.dimmed = dimmed
    }

    /// A slider takes the cursor whatever its action — ←/→ move it, Return mutes it — and
    /// so does the hero when it carries a switch. Everything else needs something to do.
    public var isSelectable: Bool {
        if case .slider = kind { return true }
        if case .hero(_, _, _, .toggle) = kind { return true }
        return action != .none
    }

    /// The slider on this row, if it is one.
    public var slider: PanelSlider? {
        if case .slider(let which, _, _) = kind { return which }
        return nil
    }

    public var sliderValue: Double? {
        if case .slider(_, let value, _) = kind { return value }
        return nil
    }

    /// What the row is, for the cursor to find it again in a rebuilt list. The hero and each
    /// slider are one of a kind — the hero's switch and the output slider share
    /// `toggleOutputMute`, so the action alone would confuse them; every other row is what
    /// its action is about, and a display row is nothing to follow.
    public var identity: String? {
        switch kind {
        case .hero:                         return "hero"
        case .slider(let which, _, _):      return "slider:\(which)"
        default:                            return action.subject
        }
    }

    // MARK: - Builders, so the panel models read as their rows

    public static func hero(glyph: String, title: String, status: String,
                            trailing: HeroTrailing? = nil, action: PanelAction = .none) -> PanelRow {
        PanelRow(.hero(glyph: glyph, title: title, status: status, trailing: trailing), action: action)
    }

    public static func header(_ text: String, trailing: String? = nil) -> PanelRow {
        PanelRow(.header(text, trailing: trailing))
    }

    public static func slider(_ which: PanelSlider, value: Double, dimmed: Bool = false,
                              action: PanelAction) -> PanelRow {
        PanelRow(.slider(which, value: max(0, min(1, value)), dimmed: dimmed), action: action)
    }

    public static func progress(_ fraction: Double) -> PanelRow {
        PanelRow(.progress(max(0, min(1, fraction))))
    }

    public static func info(_ cells: [Info]) -> PanelRow {
        PanelRow(.info(cells))
    }

    public static func pick(glyph: String, label: String, detail: String? = nil, current: Bool = false,
                            action: PanelAction, dimmed: Bool = false) -> PanelRow {
        PanelRow(.pick(glyph: glyph, label: label, detail: detail, current: current),
                 action: action, dimmed: dimmed)
    }

    public static let separator = PanelRow(.separator)

    public static func action(_ label: String, _ action: PanelAction) -> PanelRow {
        PanelRow(.action(label), action: action)
    }

    public static func note(_ text: String) -> PanelRow {
        PanelRow(.note(text))
    }

    /// The row every panel ends on: the Mac's own window for the same thing. The label names
    /// the pane the way System Settings does, so the row reads as a door and not a duplicate.
    public static func settings(_ pane: PanelSettings) -> PanelRow {
        let name: String
        switch pane {
        case .battery:   name = "Battery"
        case .displays:  name = "Displays"
        case .sound:     name = "Sound"
        case .wifi:      name = "Wi-Fi"
        case .bluetooth: name = "Bluetooth"
        }
        return .action("Open \(name) settings…", .openSettings(pane))
    }
}
