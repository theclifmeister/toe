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
/// glyph needs. RSSI, power and the link state are given freely. A captive portal is not
/// reported either — `NWPath` has no public word for it — so `restricted` is never set here,
/// and the `active` colour stays unused until it is.
final class NetworkProvider: NSObject, BarProvider, CWEventDelegate {

    private(set) var connection = BarWidgets.Connection.none
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
        connection = .none
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
        let before = connection
        defer { if connection != before { onChange?() } }
        guard let path, path.status == .satisfied else {
            connection = .none
            return
        }
        if path.usesInterfaceType(.wifi) {
            // Associated, but the RSSI not yet reported: the weakest glyph rather than none,
            // since there is a link; the next quality event corrects it.
            connection = .wifi(strength: rssi.map(BarWidgets.wifiStrength(rssi:)) ?? 1, restricted: false)
        } else if path.usesInterfaceType(.wiredEthernet) || path.usesInterfaceType(.other) {
            // `.other` is a USB or Thunderbolt adapter the system does not name as Ethernet,
            // and a tethered phone: wired, as far as the glyph is concerned.
            connection = .ethernet(restricted: false)
        } else {
            connection = .none
        }
    }
}
