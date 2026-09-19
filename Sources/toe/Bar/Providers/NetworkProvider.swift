import CoreWLAN
import Foundation
import Network
import ToeCore

/// How the machine is on the network — Omarchy's `omarchy.network`, read from `NWPathMonitor`
/// and CoreWLAN rather than NetworkManager.
///
/// Two listeners, no timer. `NWPathMonitor` says whether there is a route out and over which
/// kind of interface; CoreWLAN's event delegate says when the Wi-Fi link's quality changes,
/// which is the RSSI the signal glyph is drawn from. Both deliver off the main thread and are
/// hopped onto it here.
///
/// What a Mac will not say without a permission it is not asked for: the network's name. SSID
/// reads return nil without Location Services from macOS 14 on, and a name is not what the
/// glyph needs. RSSI, power and the link state are given freely, and so — for the panel —
/// are the channel, the band, the security, the transmit rate and the noise; see
/// `NetworkPanel` for what was measured. A captive portal is not reported either — `NWPath`
/// has no public word for it — so `restricted` is never set here, and the `active` colour
/// stays unused until it is.
final class NetworkProvider: NSObject, BarProvider, CWEventDelegate {

    /// The widget's answer, and the panel's: `link.connection` is what the glyph is drawn from.
    private(set) var link = NetworkPanel.Link(connection: .none, wifiPower: false)
    var connection: BarWidgets.Connection { link.connection }
    var onChange: (() -> Void)?

    private var monitor: NWPathMonitor?
    private var path: NWPath?
    private var rssi: Int?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                self?.path = path
                self?.update()
            }
        }
        monitor.start(queue: .global(qos: .utility))
        self.monitor = monitor

        let client = CWWiFiClient.shared()
        client.delegate = self
        // Quality is the RSSI; link and power are the association coming and going, which the
        // path monitor also notices but later, and with no RSSI to draw from until this fires.
        for event: CWEventType in [.linkQualityDidChange, .linkDidChange, .powerDidChange] {
            do { try client.startMonitoringEvent(with: event) } catch {
                Log.error("network: could not watch Wi-Fi \(event): \(error.localizedDescription)")
            }
        }
        rssi = readRSSI()
        update()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        let client = CWWiFiClient.shared()
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
        path = nil
        rssi = nil
        link = NetworkPanel.Link(connection: .none, wifiPower: false)
    }

    // MARK: - Writing

    /// The hero's switch: `CWInterface.setPower`, which needs no permission (measured for
    /// #177). The power event reports the result back.
    func toggleWifiPower() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        do { try interface.setPower(!interface.powerOn()) } catch {
            Log.error("network: could not switch Wi-Fi: \(error.localizedDescription)")
        }
    }

    // MARK: - CWEventDelegate

    func linkQualityDidChangeForWiFiInterface(withName name: String, rssi: Int, transmitRate: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.rssi = rssi
            self?.update()
        }
    }

    func linkDidChangeForWiFiInterface(withName name: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.rssi = self.readRSSI()
            self.update()
        }
    }

    func powerStateDidChangeForWiFiInterface(withName name: String) {
        linkDidChangeForWiFiInterface(withName: name)
    }

    // MARK: - Reading

    /// nil when the interface is off or not associated — `rssiValue` answers 0 then, which
    /// would read as a full signal.
    private func readRSSI() -> Int? {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return nil }
        let value = interface.rssiValue()
        return value == 0 ? nil : value
    }

    private func update() {
        let before = link
        defer { if link != before { onChange?() } }
        let interface = CWWiFiClient.shared().interface()
        var next = NetworkPanel.Link(connection: .none, wifiPower: interface?.powerOn() ?? false)
        guard let path, path.status == .satisfied else {
            link = next
            return
        }
        if path.usesInterfaceType(.wifi) {
            // Associated, but the RSSI not yet reported: the weakest glyph rather than none,
            // since there is a link; the next quality event corrects it.
            next.connection = .wifi(strength: rssi.map(BarWidgets.wifiStrength(rssi:)) ?? 1, restricted: false)
            if let interface {
                next.interfaceName = interface.interfaceName
                next.rssi = rssi
                let noise = interface.noiseMeasurement()
                next.noise = noise == 0 ? nil : noise
                if let channel = interface.wlanChannel() {
                    next.channel = channel.channelNumber
                    switch channel.channelBand {
                    case .band2GHz: next.band = .ghz2_4
                    case .band5GHz: next.band = .ghz5
                    case .band6GHz: next.band = .ghz6
                    default: next.band = nil
                    }
                }
                next.security = Self.name(of: interface.security())
                let rate = interface.transmitRate()
                next.transmitRate = rate > 0 ? rate : nil
                next.address = Self.address(of: interface.interfaceName)
            }
        } else if path.usesInterfaceType(.wiredEthernet) || path.usesInterfaceType(.other) {
            // `.other` is a USB or Thunderbolt adapter the system does not name as Ethernet,
            // and a tethered phone: wired, as far as the glyph is concerned.
            next.connection = .ethernet(restricted: false)
            let wired = path.availableInterfaces.first { $0.type == .wiredEthernet || $0.type == .other }
            next.interfaceName = wired?.name
            next.address = Self.address(of: wired?.name)
        }
        link = next
    }

    /// `CWSecurity` in System Settings' words. Everything else is a Mac saying what it is
    /// but not in a way a person recognises, and the raw value is more honest than a guess.
    private static func name(of security: CWSecurity) -> String? {
        switch security {
        case .none: return "Open"
        case .WEP: return "WEP"
        case .wpaPersonal: return "WPA Personal"
        case .wpaPersonalMixed: return "WPA/WPA2 Personal"
        case .wpa2Personal: return "WPA2 Personal"
        case .personal: return "Personal"
        case .dynamicWEP: return "Dynamic WEP"
        case .wpaEnterprise: return "WPA Enterprise"
        case .wpaEnterpriseMixed: return "WPA/WPA2 Enterprise"
        case .wpa2Enterprise: return "WPA2 Enterprise"
        case .enterprise: return "Enterprise"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        case .wpa3Transition: return "WPA2/WPA3 Personal"
        case .OWE: return "Enhanced Open"
        case .oweTransition: return "Open/Enhanced Open"
        case .unknown: return nil
        @unknown default: return nil
        }
    }

    /// The interface's IPv4 address from `getifaddrs` — the one thing upstream's stats show
    /// that a Mac gives without asking anyone.
    private static func address(of interface: String?) -> String? {
        guard let interface else { return nil }
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == interface,
                  let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }
}
