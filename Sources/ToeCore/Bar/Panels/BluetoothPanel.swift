import Foundation

/// The Bluetooth panel — `panels/bluetooth/Panel.qml`, behind the one permission toe asks for
/// on a panel rather than at launch.
///
/// Upstream is the adapter's switch, then the connected devices, the paired ones and — while
/// scanning — the discovered ones, each with connect, disconnect and forget. What a Mac exposes
/// publicly, once the Bluetooth grant exists: the adapter's power (read, not written — setting
/// it is a private preference call), the paired devices and whether each is connected, and
/// `openConnection` / `closeConnection` on any of them. No discovery, no pairing and no
/// forgetting: those are System Settings' by design, and the door is there for them.
///
/// The grant is the point of this panel — #177: the widget draws the generic "on" glyph until
/// the first time the panel is opened, macOS asks then and not at launch, and the panel says
/// where it stands while the answer is pending, and afterwards when it is no.
public enum BluetoothPanel {

    /// `CBManagerAuthorization`, as the panel needs it.
    public enum Access: Equatable, Sendable {
        /// Never asked, or asked and the sheet is still up.
        case undetermined
        case denied
        case granted
        /// A Mac with no adapter at all.
        case unavailable
    }

    public struct Device: Equatable, Sendable {
        /// `IOBluetoothDevice.addressString`, the one name a device keeps.
        public var address: String
        public var name: String
        public var connected: Bool

        public init(address: String, name: String, connected: Bool) {
            self.address = address
            self.name = name
            self.connected = connected
        }
    }

    /// What `BluetoothProvider` reads: whether it may, whether the radio is on, and the paired
    /// devices. `devices` is empty until the grant exists.
    public struct State: Equatable, Sendable {
        public var access: Access
        public var powered: Bool
        public var devices: [Device]

        public init(access: Access, powered: Bool = false, devices: [Device] = []) {
            self.access = access
            self.powered = powered
            self.devices = devices
        }

        /// The connected count the widget's glyph rule takes.
        public var connected: Int { devices.filter(\.connected).count }
    }

    /// `deviceLists`: connected first, then the rest of the paired, each sorted by name — and
    /// nothing without a human name, which upstream drops too.
    public static func lists(_ devices: [Device]) -> (connected: [Device], paired: [Device]) {
        let named = devices.filter { !$0.name.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (named.filter(\.connected), named.filter { !$0.connected })
    }

    /// `heroStatusText`, with the rotating phrases ("Herding headsets") left out for the reason
    /// the power panel's are.
    public static func status(_ s: State) -> String {
        switch s.access {
        case .undetermined: return "Asking for access"
        case .denied:       return "Access denied"
        case .unavailable:  return "No adapter"
        case .granted:
            if !s.powered { return "Turned off" }
            let n = s.connected
            return n == 0 ? "On" : (n == 1 ? "1 connected" : "\(n) connected")
        }
    }

    public static func rows(_ s: State) -> [PanelRow] {
        // The glyph is the widget's — which is the generic "on" until the grant exists, since
        // toe cannot know better and "off" would be a claim.
        let glyph = s.access == .granted
            ? (!s.powered ? Glyphs.bluetoothOff : (s.connected > 0 ? Glyphs.bluetoothConnected : Glyphs.bluetoothOn))
            : Glyphs.bluetoothOn
        var rows: [PanelRow] = [.hero(glyph: glyph, title: "Bluetooth", status: status(s))]
        switch s.access {
        case .undetermined:
            rows += [.separator, .note("macOS is asking whether toe may use Bluetooth.")]
        case .denied:
            rows += [.separator, .note("Allow toe under Privacy & Security › Bluetooth.")]
        case .unavailable:
            rows += [.separator, .note("This Mac has no Bluetooth adapter.")]
        case .granted:
            let (connected, paired) = lists(s.devices)
            if !connected.isEmpty {
                rows += [.separator, .header("Connected")]
                rows += connected.map {
                    .pick(glyph: Glyphs.bluetoothConnected, label: $0.name, detail: "Connected", current: true,
                          action: .disconnectBluetooth($0.address))
                }
            }
            if !paired.isEmpty {
                rows += [.separator, .header("Paired")]
                rows += paired.map {
                    .pick(glyph: Glyphs.bluetoothOn, label: $0.name, action: .connectBluetooth($0.address),
                          dimmed: !s.powered)
                }
            }
        }
        rows += [.separator, .settings(.bluetooth)]
        return rows
    }
}
