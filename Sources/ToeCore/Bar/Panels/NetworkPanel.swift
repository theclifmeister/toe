import Foundation

/// The network panel — `panels/network/Panel.qml`, cut to what a Mac says without Location.
///
/// Upstream is the connected network's name and state with a Wi-Fi switch, the connection's
/// numbers, a band picker, a DNS picker, and the networks in range to join. On macOS 14 and
/// later a network's name — the SSID, the BSSID, the names in a scan — is behind Location
/// Services, and #177 settled that toe does not ask for a third permission for it: a widget
/// that draws a signal should not ask where you are. Measured on this machine for #177: with
/// Location not determined, `ssid()` and `bssid()` are nil and every one of a scan's fourteen
/// networks has a nil name, while the RSSI, the channel and band, the security, the transmit
/// rate and the noise are all given. A scan also blocks for seven seconds, which is seven
/// seconds the main thread cannot spare. So this panel is the connection: what it is, its
/// switch, its numbers, and the Wi-Fi pane for everything that needs a name.
public enum NetworkPanel {

    /// The Wi-Fi band, `CWChannelBand`.
    public enum Band: Equatable, Sendable {
        case ghz2_4, ghz5, ghz6
        public var label: String {
            switch self {
            case .ghz2_4: return "2.4 GHz"
            case .ghz5:   return "5 GHz"
            case .ghz6:   return "6 GHz"
            }
        }
    }

    /// What `NetworkProvider` reads about the link: the widget's `Connection`, and the numbers
    /// a Mac gives freely about a Wi-Fi association.
    public struct Link: Equatable, Sendable {
        public var connection: BarWidgets.Connection
        /// `CWInterface.powerOn()` — the hero's switch.
        public var wifiPower: Bool
        public var interfaceName: String?
        public var rssi: Int?
        public var noise: Int?
        public var band: Band?
        public var channel: Int?
        /// `CWSecurity`, named: "WPA2 Personal", "WPA3 Personal", "Open".
        public var security: String?
        /// `transmitRate()`, in Mbit/s.
        public var transmitRate: Double?
        /// The interface's IPv4 address, from `getifaddrs`.
        public var address: String?

        public init(connection: BarWidgets.Connection, wifiPower: Bool, interfaceName: String? = nil,
                    rssi: Int? = nil, noise: Int? = nil, band: Band? = nil, channel: Int? = nil,
                    security: String? = nil, transmitRate: Double? = nil, address: String? = nil) {
            self.connection = connection
            self.wifiPower = wifiPower
            self.interfaceName = interfaceName
            self.rssi = rssi
            self.noise = noise
            self.band = band
            self.channel = channel
            self.security = security
            self.transmitRate = transmitRate
            self.address = address
        }
    }

    /// The hero's title — the network's name upstream, which a Mac will not say, so the kind
    /// of link — and its status line.
    public static func title(_ l: Link) -> String {
        switch l.connection {
        case .wifi:     return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .none:     return l.wifiPower ? "Not connected" : "Wi-Fi off"
        }
    }

    public static func status(_ l: Link) -> String {
        switch l.connection {
        case .wifi(_, let restricted), .ethernet(let restricted):
            return restricted ? "Limited internet access" : "Connected"
        case .none:
            return l.wifiPower ? "Not connected" : "Turned off"
        }
    }

    /// `formatHeaderSpeed`: "516 Mbit/s", "1 Gbit/s", "2.5 Gbit/s".
    public static func rateLabel(_ mbps: Double) -> String {
        guard mbps > 0 else { return "—" }
        if mbps >= 1000 {
            let gbit = mbps / 1000
            return (gbit == gbit.rounded() ? String(Int(gbit)) : String(format: "%.1f", gbit)) + " Gbit/s"
        }
        return "\(Int(mbps.rounded())) Mbit/s"
    }

    /// "−54 dBm, 92%": the RSSI and the strength the widget draws it as.
    public static func signalLabel(rssi: Int) -> String {
        "\u{2212}\(abs(rssi)) dBm, \(BarWidgets.wifiStrength(rssi: rssi))%"
    }

    public static func rows(_ l: Link) -> [PanelRow] {
        var rows: [PanelRow] = [
            .hero(glyph: BarWidgets.networkGlyph(l.connection), title: title(l), status: status(l),
                  trailing: .toggle(on: l.wifiPower), action: .toggleWifi),
        ]
        if case .wifi = l.connection {
            var stats: [PanelRow.Info] = []
            if let rssi = l.rssi { stats.append(PanelRow.Info("Signal", signalLabel(rssi: rssi))) }
            if let noise = l.noise { stats.append(PanelRow.Info("Noise", "\u{2212}\(abs(noise)) dBm")) }
            if let channel = l.channel {
                stats.append(PanelRow.Info("Channel", l.band.map { "\(channel), \($0.label)" } ?? String(channel)))
            }
            if let rate = l.transmitRate { stats.append(PanelRow.Info("Rate", rateLabel(rate))) }
            if let security = l.security { stats.append(PanelRow.Info("Security", security)) }
            if let address = l.address { stats.append(PanelRow.Info("IP address", address)) }
            if !stats.isEmpty {
                rows.append(.separator)
                for pair in stride(from: 0, to: stats.count, by: 2) {
                    rows.append(.info(Array(stats[pair..<min(pair + 2, stats.count)])))
                }
            }
            // Said once, quietly, so the missing name reads as a choice and not a bug.
            rows += [.separator, .note("Names need Location, which toe does not ask for.")]
        } else if case .ethernet = l.connection {
            var stats: [PanelRow.Info] = []
            if let name = l.interfaceName { stats.append(PanelRow.Info("Interface", name)) }
            if let address = l.address { stats.append(PanelRow.Info("IP address", address)) }
            if !stats.isEmpty { rows += [.separator, .info(stats)] }
        }
        rows += [.separator, .settings(.wifi)]
        return rows
    }
}
