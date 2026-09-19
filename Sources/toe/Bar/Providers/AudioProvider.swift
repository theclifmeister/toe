import AudioToolbox
import CoreAudio
import Foundation
import ToeCore

/// The default output device's volume and mute, and the device lists, from CoreAudio —
/// Omarchy's `omarchy.audio`, read from the HAL rather than PipeWire.
///
/// Property listeners and no timer: three on the system object — the default output changing,
/// the default input changing, the device list changing — and two each on the current default
/// output and input for their volume and mute. A device's pair are re-registered on the device
/// that is current, because a listener is per object and a new default device is a new object.
/// Every callback is delivered on the main queue, which is what
/// `AudioObjectAddPropertyListenerBlock` takes a queue for.
///
/// `state` is nil while there is no output device at all — a Mac with its only device gone —
/// and the widget is then not listed. The device lists are read on every change rather than
/// held, since a change is what the listener said happened, and the list is a dozen devices.
final class AudioProvider: BarProvider {

    private(set) var state: AudioPanel.State?
    var onChange: (() -> Void)?

    private var output = AudioObjectID(kAudioObjectUnknown)
    private var input = AudioObjectID(kAudioObjectUnknown)
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var inputListener: AudioObjectPropertyListenerBlock?

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static let defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice)
    private static let defaultInput = address(kAudioHardwarePropertyDefaultInputDevice)
    private static let deviceList = address(kAudioHardwarePropertyDevices)
    private static let outputVolume = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
    private static let outputMute = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput)
    private static let inputVolume = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeInput)
    private static let inputMute = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
    private static let transport = address(kAudioDevicePropertyTransportType)
    private static let dataSource = address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)
    private static let name = address(kAudioObjectPropertyName)

    func start() {
        guard systemListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.systemChanged() }
        for var address in [Self.defaultOutput, Self.defaultInput, Self.deviceList] {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        systemListener = listener
        systemChanged()
    }

    func stop() {
        if let systemListener {
            for var address in [Self.defaultOutput, Self.defaultInput, Self.deviceList] {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
            }
            self.systemListener = nil
        }
        unwatch(&output, &outputListener, [Self.outputVolume, Self.outputMute, Self.dataSource])
        unwatch(&input, &inputListener, [Self.inputVolume, Self.inputMute])
        state = nil
    }

    // MARK: - Writing

    /// Right click on the widget, Return on the output slider, the hero's switch.
    func toggleMute() {
        guard output != kAudioObjectUnknown, let state else { return }
        set(output, Self.outputMute, UInt32(state.muted ? 0 : 1))
    }

    func toggleInputMute() {
        guard input != kAudioObjectUnknown, let state else { return }
        set(input, Self.inputMute, UInt32(state.inputMuted ? 0 : 1))
    }

    /// The wheel: 5% a notch, as upstream's `wheelSteps × 0.05`, clamped.
    func adjustVolume(steps: Int) {
        guard let state, steps != 0 else { return }
        setVolume(state.volume + Double(steps) * 0.05)
    }

    /// The panel's slider: the volume outright, clamped. The device's own listener reports
    /// the value back, which is what redraws the widget and the panel.
    func setVolume(_ volume: Double) {
        guard output != kAudioObjectUnknown else { return }
        set(output, Self.outputVolume, Float32(max(0, min(1, volume))))
    }

    func setInputVolume(_ volume: Double) {
        guard input != kAudioObjectUnknown else { return }
        set(input, Self.inputVolume, Float32(max(0, min(1, volume))))
    }

    /// A device row pressed: the system's default, which is what the volume keys and every
    /// application follow. The system object's listener reports it back.
    func setDefaultOutput(_ id: UInt32) {
        set(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput, AudioObjectID(id))
    }

    func setDefaultInput(_ id: UInt32) {
        set(AudioObjectID(kAudioObjectSystemObject), Self.defaultInput, AudioObjectID(id))
    }

    private func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) {
        var value = value
        var address = address
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    // MARK: - Reading

    private func systemChanged() {
        let newOutput = Self.get(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput, AudioObjectID(kAudioObjectUnknown))
        let newInput = Self.get(AudioObjectID(kAudioObjectSystemObject), Self.defaultInput, AudioObjectID(kAudioObjectUnknown))
        if newOutput != output {
            unwatch(&output, &outputListener, [Self.outputVolume, Self.outputMute, Self.dataSource])
            output = newOutput
            outputListener = watch(output, [Self.outputVolume, Self.outputMute, Self.dataSource])
        }
        if newInput != input {
            unwatch(&input, &inputListener, [Self.inputVolume, Self.inputMute])
            input = newInput
            inputListener = watch(input, [Self.inputVolume, Self.inputMute])
        }
        read()
    }

    private func watch(_ device: AudioObjectID, _ addresses: [AudioObjectPropertyAddress]) -> AudioObjectPropertyListenerBlock? {
        guard device != kAudioObjectUnknown else { return nil }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read() }
        for var address in addresses {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
        return listener
    }

    private func unwatch(_ device: inout AudioObjectID, _ listener: inout AudioObjectPropertyListenerBlock?,
                         _ addresses: [AudioObjectPropertyAddress]) {
        if device != kAudioObjectUnknown, let listener {
            for var address in addresses {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            }
        }
        listener = nil
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func read() {
        let before = state
        defer { if state != before { onChange?() } }
        guard output != kAudioObjectUnknown else {
            state = nil
            return
        }
        let (outputs, inputs) = Self.devices()
        var next = AudioPanel.State(
            volume: Double(Self.get(output, Self.outputVolume, Float32(0))),
            muted: Self.get(output, Self.outputMute, UInt32(0)) != 0,
            outputs: outputs, defaultOutput: output,
            inputs: inputs)
        if input != kAudioObjectUnknown {
            next.inputVolume = Double(Self.get(input, Self.inputVolume, Float32(0)))
            next.inputMuted = Self.get(input, Self.inputMute, UInt32(0)) != 0
            next.defaultInput = input
        }
        state = next
    }

    /// Every device with at least one output channel, and every one with at least one input
    /// — `kAudioDevicePropertyStreamConfiguration` per scope, which is how CoreAudio says
    /// which way a device faces. Named as the device names itself; a built-in device whose
    /// data source is the headphone jack is marked, since that is the one thing a Mac says
    /// outright about headphones.
    private static func devices() -> (outputs: [AudioPanel.Device], inputs: [AudioPanel.Device]) {
        var address = Self.deviceList
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return ([], [])
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return ([], [])
        }
        var outputs: [AudioPanel.Device] = []
        var inputs: [AudioPanel.Device] = []
        for id in ids {
            let name = Self.name(of: id)
            // No name is an aggregate or a driver's private endpoint, not a thing to pick.
            guard !name.isEmpty else { continue }
            let transport = Self.transport(of: id)
            let jack = transport == .builtIn
                && Self.get(id, Self.dataSource, UInt32(0)) == 0x6864706E /* 'hdpn' */
            let device = AudioPanel.Device(id: id, name: name, transport: transport, jack: jack)
            if channels(of: id, scope: kAudioObjectPropertyScopeOutput) > 0 { outputs.append(device) }
            if channels(of: id, scope: kAudioObjectPropertyScopeInput) > 0 { inputs.append(device) }
        }
        return (outputs, inputs)
    }

    private static func channels(of device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let list = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func name(of device: AudioObjectID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = Self.name
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let text = name?.takeRetainedValue() as String? else { return "" }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func transport(of device: AudioObjectID) -> AudioPanel.Transport {
        switch get(device, Self.transport, UInt32(0)) {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        default: return .other
        }
    }

    /// One property of a fixed size, or `fallback` when the object has not got it.
    private static func get<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ fallback: T) -> T {
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        var address = address
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return fallback }
        return value
    }
}
