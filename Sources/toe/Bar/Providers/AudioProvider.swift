import AudioToolbox
import CoreAudio
import Foundation
import ToeCore

/// The default output device's volume and mute, and the device lists, from CoreAudio —
/// Omarchy's `omarchy.audio`, read from the HAL rather than PipeWire.
///
/// Property listeners and no timer: three on the system object — the default output changing,
/// the default input changing, the device list changing — and a handful each on the current
/// default output and input for their volume and mute, the virtual main volume and every
/// element's scalar and mute through a wildcard. A device's set are re-registered on the device
/// that is current, because a listener is per object and a new default device is a new object.
/// Every callback is delivered on the main queue, which is what
/// `AudioObjectAddPropertyListenerBlock` takes a queue for.
///
/// `state` is nil while there is no output device at all — a Mac with its only device gone —
/// and the widget is then not listed. The device lists are read on every change rather than
/// held, since a change is what the listener said happened, and the list is a dozen devices.
///
/// Not every device has a volume. A Focusrite Scarlett, most USB interfaces and DACs, and an
/// HDMI sink leave the level to a knob, and the HAL answers `VirtualMainVolume` with an error;
/// the fallback of 0 drew such a device as muted while it played. So the volume and the mute
/// are looked for before they are read — `AudioObjectIsPropertySettable` on the main element
/// and then on each channel, since a device may carry its controls per channel and no main
/// one — and a device with no volume anywhere is `fixedVolume`, which is not a level.
final class AudioProvider: BarProvider {

    private(set) var state: AudioPanel.State?
    var onChange: (() -> Void)?

    private var output = AudioObjectID(kAudioObjectUnknown)
    private var input = AudioObjectID(kAudioObjectUnknown)
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var inputListener: AudioObjectPropertyListenerBlock?

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static let defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice)
    private static let defaultInput = address(kAudioHardwarePropertyDefaultInputDevice)
    private static let deviceList = address(kAudioHardwarePropertyDevices)
    private static let outputVolume = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput)
    private static let inputVolume = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeInput)
    /// Every channel's volume and mute, for the listeners only: a device whose controls are
    /// per channel reports a change on the channel, not on the main element. A wildcard is
    /// what a listener takes for "any element"; a read or a write needs a real one.
    private static let outputChannels = [address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementWildcard),
                                         address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementWildcard)]
    private static let inputChannels = [address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementWildcard),
                                        address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementWildcard)]
    private static let outputWatched = [outputVolume, dataSource] + outputChannels
    private static let inputWatched = [inputVolume] + inputChannels
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
        unwatch(&output, &outputListener, Self.outputWatched)
        unwatch(&input, &inputListener, Self.inputWatched)
        state = nil
    }

    // MARK: - Writing

    /// Right click on the widget, Return on the output slider, the hero's switch. Every mute
    /// the device has, main or per channel, so that a device muted channel by channel is
    /// unmuted the same way; nothing at all on a device that has none.
    func toggleMute() {
        guard output != kAudioObjectUnknown, let state, state.canMute else { return }
        writeMute(output, kAudioObjectPropertyScopeOutput, !state.muted)
    }

    func toggleInputMute() {
        guard input != kAudioObjectUnknown, let state else { return }
        writeMute(input, kAudioObjectPropertyScopeInput, !state.inputMuted)
    }

    /// The wheel: 5% a notch, as upstream's `wheelSteps × 0.05`, clamped. A fixed device has
    /// no volume to step from — `state.volume` is the 0 nothing was read into.
    func adjustVolume(steps: Int) {
        guard let state, !state.fixedVolume, steps != 0 else { return }
        setVolume(state.volume + Double(steps) * 0.05)
    }

    /// The panel's slider: the volume outright, clamped. The device's own listener reports
    /// the value back, which is what redraws the widget and the panel.
    func setVolume(_ volume: Double) {
        guard output != kAudioObjectUnknown else { return }
        writeVolume(output, kAudioObjectPropertyScopeOutput, volume)
    }

    func setInputVolume(_ volume: Double) {
        guard input != kAudioObjectUnknown else { return }
        writeVolume(input, kAudioObjectPropertyScopeInput, volume)
    }

    /// `VirtualMainVolume` where the device will take it — it is the HAL's own reconciliation
    /// of a main control and per-channel ones, balance kept — and each channel's scalar where
    /// only those can be set. A fixed device has neither, and the write is skipped rather
    /// than sent to fail.
    private func writeVolume(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ volume: Double) {
        let value = Float32(max(0, min(1, volume)))
        let virtual = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if Self.settable(device, virtual) {
            set(device, virtual, value)
            return
        }
        for element in Self.controls(device, kAudioDevicePropertyVolumeScalar, scope) {
            set(device, Self.address(kAudioDevicePropertyVolumeScalar, scope, element), value)
        }
    }

    private func writeMute(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ muted: Bool) {
        for element in Self.controls(device, kAudioDevicePropertyMute, scope) {
            set(device, Self.address(kAudioDevicePropertyMute, scope, element), UInt32(muted ? 1 : 0))
        }
    }

    /// A device row pressed: the system's default, which is what the volume keys and every
    /// application follow. The system object's listener reports it back.
    func setDefaultOutput(_ id: UInt32) {
        set(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput, AudioObjectID(id))
    }

    func setDefaultInput(_ id: UInt32) {
        set(AudioObjectID(kAudioObjectSystemObject), Self.defaultInput, AudioObjectID(id))
    }

    /// `T` is only ever a `Float32` or a `UInt32` — a plain number the HAL copies — which is
    /// what the pointer needs and what the generic cannot promise, hence the trivial check.
    private func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) {
        precondition(_isPOD(T.self), "a CoreAudio property is a plain value")
        var value = value
        var address = address
        withUnsafeMutablePointer(to: &value) { pointer in
            _ = AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), pointer)
        }
    }

    // MARK: - Reading

    private func systemChanged() {
        let newOutput = Self.get(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutput, AudioObjectID(kAudioObjectUnknown))
        let newInput = Self.get(AudioObjectID(kAudioObjectSystemObject), Self.defaultInput, AudioObjectID(kAudioObjectUnknown))
        if newOutput != output {
            unwatch(&output, &outputListener, Self.outputWatched)
            output = newOutput
            outputListener = watch(output, Self.outputWatched)
        }
        if newInput != input {
            unwatch(&input, &inputListener, Self.inputWatched)
            input = newInput
            inputListener = watch(input, Self.inputWatched)
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
        let volume = Self.volume(of: output, kAudioObjectPropertyScopeOutput)
        let mute = Self.mute(of: output, kAudioObjectPropertyScopeOutput)
        var next = AudioPanel.State(
            volume: volume ?? 0, muted: mute ?? false,
            outputs: outputs, defaultOutput: output,
            inputs: inputs,
            fixedVolume: volume == nil, canMute: mute != nil)
        if input != kAudioObjectUnknown {
            let inputVolume = Self.volume(of: input, kAudioObjectPropertyScopeInput)
            next.inputVolume = inputVolume ?? 0
            next.inputFixedVolume = inputVolume == nil
            next.inputMuted = Self.mute(of: input, kAudioObjectPropertyScopeInput) ?? false
            next.defaultInput = input
        }
        state = next
    }

    /// The volume in `scope`, or nil when the device has none that can be set — the fixed
    /// case, which must not read as 0. `VirtualMainVolume` first; failing that the mean of
    /// the channels' own scalars, which is what the virtual property would have said.
    private static func volume(of device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Double? {
        let virtual = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if settable(device, virtual) { return Double(get(device, virtual, Float32(0))) }
        let elements = controls(device, kAudioDevicePropertyVolumeScalar, scope)
        guard !elements.isEmpty else { return nil }
        let sum = elements.reduce(0.0) {
            $0 + Double(get(device, address(kAudioDevicePropertyVolumeScalar, scope, $1), Float32(0)))
        }
        return sum / Double(elements.count)
    }

    /// Whether `scope` is muted, or nil when the device has no mute that can be set. Muted
    /// per channel means every channel muted — one channel off is a balance, not a mute.
    private static func mute(of device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool? {
        let elements = controls(device, kAudioDevicePropertyMute, scope)
        guard !elements.isEmpty else { return nil }
        return elements.allSatisfy { get(device, address(kAudioDevicePropertyMute, scope, $0), UInt32(0)) != 0 }
    }

    /// The elements of `selector` in `scope` that can be set: the main element when there is
    /// one, which stands for the lot, and otherwise each channel, 1…n, that has its own. Empty
    /// is a device with no such control anywhere. A property that is there but read-only — a
    /// volume a driver reports and will not take — counts as absent, as System Settings counts
    /// it when it greys the slider.
    private static func controls(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 _ scope: AudioObjectPropertyScope) -> [AudioObjectPropertyElement] {
        if settable(device, address(selector, scope)) { return [kAudioObjectPropertyElementMain] }
        let count = channels(of: device, scope: scope)
        guard count > 0 else { return [] }
        return (1...UInt32(count)).filter { settable(device, address(selector, scope, $0)) }
    }

    private static func settable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
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
        precondition(_isPOD(T.self), "a CoreAudio property is a plain value")
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        var address = address
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value : fallback
    }
}
