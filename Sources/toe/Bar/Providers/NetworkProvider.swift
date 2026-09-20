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
/// One exception, for the panel and only while it is open: the traffic graph (#189) needs the
/// interface's byte counters once a second, and a byte counter has no listener — nothing in
/// the system says "the number went up". So `startTraffic` is the `MenuBarPeek` shape, a timer
/// that runs only while there is something to show it to: `Coordinator.openPanel(.network)`
/// starts it, closing the panel or switching it to another widget stops it, and `start` —
/// what the bar needs — never touches it. The glyph does not need the counters.
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

    /// The last minute on the link, sampled while the panel is open; `traffic.window` is what
    /// the graph row carries. Fresh on every `startTraffic`, so a panel opens on an empty
    /// graph that fills, not on the minute before it was last closed.
    private(set) var traffic = NetworkTraffic()
    private var trafficTimer: Timer?

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
        stopTraffic()
        monitor?.cancel()
        monitor = nil
        let client = CWWiFiClient.shared()
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
        path = nil
        rssi = nil
        link = NetworkPanel.Link(connection: .none, wifiPower: false)
    }

    // MARK: - Traffic

    /// Begins sampling the link's counters once a second, with the first reading taken now so
    /// the first delta is a second away rather than two. Idempotent: the panel switching from
    /// the network panel to itself does not restart the ring.
    func startTraffic() {
        guard trafficTimer == nil else { return }
        traffic = NetworkTraffic()
        sampleTraffic()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sampleTraffic() }
        // `.common`, as the clock's: the panel stays live while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        trafficTimer = timer
    }

    /// Stops the sampling and forgets the minute. Every way the panel goes — Escape, a click
    /// elsewhere, `bar hide`, a screen change, fullscreen on its display, a switch to another
    /// widget — comes through here, since `BarPanelWindow.close` is the one door out and the
    /// Coordinator watches it; `log stream` should show nothing ticking once the panel is gone.
    func stopTraffic() {
        trafficTimer?.invalidate()
        trafficTimer = nil
        traffic = NetworkTraffic()
    }

    private func sampleTraffic() {
        // No interface, nothing to count: the ring keeps what it has, and the panel is showing
        // no graph for a `.none` link anyway. The next link's first reading starts it fresh —
        // `NetworkTraffic.push` sees a new interface name.
        guard let name = link.interfaceName, let counters = Self.readCounters(for: name) else { return }
        traffic.push(NetworkTraffic.Reading(interface: name, inBytes: counters.inBytes, outBytes: counters.outBytes,
                                            at: ProcessInfo.processInfo.systemUptime))
        if let current = traffic.window.current {
            Log.info("network: traffic on \(name) \(NetworkTraffic.rateLabel(current.down)) down, \(NetworkTraffic.rateLabel(current.up)) up")
        }
        onChange?()
    }

    /// The interface's lifetime bytes in and out, from `sysctl NET_RT_IFLIST2`.
    ///
    /// Not `getifaddrs`: its `ifa_data` is an `if_data` whose counters are 32-bit and wrap at
    /// 4 GiB, which on a link doing a hundred megabytes a second is every forty seconds — a
    /// wrap the ring would read as a reset and draw as a zero. `RTM_IFINFO2` carries
    /// `if_data64`, and the same route socket dump is what `netstat -ib` reads. Public, and
    /// no permission: the panel rule from #180 holds.
    ///
    /// The dump is one message per interface, each an `if_msghdr2` followed by its addresses,
    /// and each `ifm_msglen` long; the interface is found by index rather than by name because
    /// the name is not in the message — it is in the `sockaddr_dl` after it — and
    /// `if_nametoindex` is the cheaper lookup. `loadUnaligned`, because a message's offset is
    /// whatever the previous lengths add up to and `if_data64` wants eight-byte alignment.
    static func readCounters(for interface: String) -> (inBytes: UInt64, outBytes: UInt64)? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> (inBytes: UInt64, outBytes: UInt64)? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                // A zero length would loop here forever; the kernel does not write one, but
                // the loop's exit should not depend on that.
                guard header.ifm_msglen > 0 else { return nil }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if message.ifm_index == UInt16(index) {
                        return (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
            return nil
        }
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
