import CoreBluetooth
import Foundation
import IOBluetooth
import ToeCore

/// Bluetooth — Omarchy's `omarchy.bluetooth`, from IOBluetooth rather than BlueZ, and the one
/// provider that starts late.
///
/// Every public Bluetooth read on current macOS — `IOBluetoothHostController`,
/// `IOBluetoothDevice.pairedDevices()` — sits behind the Bluetooth TCC grant, and asking for it
/// is a sheet with toe's name on it. #177 settled that the sheet comes the first time the
/// Bluetooth panel is opened, not at launch: `start()` does nothing but read
/// `CBCentralManager.authorization`, which is free, and the widget draws the generic "on"
/// glyph until there is a grant to draw from. `request()` — the panel opening — makes the
/// `CBCentralManager` whose creation is what puts the sheet up, and its delegate says how it
/// went. A grant given in an earlier run is remembered by TCC, so the second launch starts the
/// real reads at once and the widget is right from the first frame.
///
/// Once granted: the paired devices from `IOBluetoothDevice.pairedDevices()`, connects from
/// the class-wide connect notification, disconnects from a per-device registration made when a
/// device is seen connected, and the radio's power from the central manager's state. No
/// polling, and no discovery — pairing is System Settings'.
final class BluetoothProvider: NSObject, BarProvider, CBCentralManagerDelegate {

    private(set) var state = BluetoothPanel.State(access: .undetermined)
    var onChange: (() -> Void)?

    private var central: CBCentralManager?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private let queue = DispatchQueue(label: "com.clifmeister.toe.bluetooth", qos: .userInitiated)

    /// Free: reads the remembered answer and starts the real reads only on a yes.
    func start() {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            request()
        case .denied, .restricted:
            state = BluetoothPanel.State(access: .denied)
        case .notDetermined:
            state = BluetoothPanel.State(access: .undetermined)
        @unknown default:
            state = BluetoothPanel.State(access: .undetermined)
        }
    }

    func stop() {
        central?.delegate = nil
        central = nil
        connectNotification?.unregister()
        connectNotification = nil
        for notification in disconnectNotifications.values { notification.unregister() }
        disconnectNotifications = [:]
        state = BluetoothPanel.State(access: .undetermined)
    }

    /// Whether a panel opening should ask: never asked yet. Denied stays denied — macOS does
    /// not ask twice, and the panel points at the pane where the answer is changed.
    var needsRequest: Bool { central == nil && CBCentralManager.authorization == .notDetermined }

    /// The first open of the panel, or a launch with the grant already given. Making the
    /// central manager is the ask; `centralManagerDidUpdateState` is the answer.
    func request() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    // MARK: - Writing

    /// A paired device row: `openConnection` blocks for as long as the device takes to answer
    /// — seconds, for a pair of headphones in a drawer — so it runs off the main thread and
    /// the connect notification reports the result. `closeConnection` the same way, for
    /// symmetry rather than need.
    func connect(_ address: String) {
        queue.async {
            guard let device = IOBluetoothDevice(addressString: address) else { return }
            let result = device.openConnection()
            if result != kIOReturnSuccess { Log.error("bluetooth: could not connect \(address): \(result)") }
        }
    }

    func disconnect(_ address: String) {
        queue.async {
            guard let device = IOBluetoothDevice(addressString: address) else { return }
            let result = device.closeConnection()
            if result != kIOReturnSuccess { Log.error("bluetooth: could not disconnect \(address): \(result)") }
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unauthorized:
            state = BluetoothPanel.State(access: .denied)
            onChange?()
        case .unsupported:
            state = BluetoothPanel.State(access: .unavailable)
            onChange?()
        case .poweredOn, .poweredOff, .resetting:
            watch()
            read(powered: central.state == .poweredOn)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Reading

    private func watch() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in self?.changed() }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in self?.changed() }
    }

    private func changed() {
        read(powered: central?.state == .poweredOn)
    }

    private func read(powered: Bool) {
        let before = state
        defer { if state != before { onChange?() } }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        var devices: [BluetoothPanel.Device] = []
        for device in paired {
            guard let address = device.addressString else { continue }
            let connected = device.isConnected()
            devices.append(BluetoothPanel.Device(address: address, name: device.name ?? "", connected: connected))
            // A disconnect notification is per device and per connection: registered when
            // the device is seen connected, and IOBluetooth drops it when the connection goes.
            if connected, disconnectNotifications[address] == nil,
               let note = device.register(forDisconnectNotification: self,
                                          selector: #selector(deviceDisconnected(_:device:))) {
                disconnectNotifications[address] = note
            } else if !connected {
                disconnectNotifications.removeValue(forKey: address)
            }
        }
        state = BluetoothPanel.State(access: .granted, powered: powered, devices: devices)
    }
}
