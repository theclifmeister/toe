import AudioToolbox
import CoreAudio
import Foundation
import ToeCore

/// The default output device's volume and mute, from CoreAudio — Omarchy's `omarchy.audio`,
/// read from the HAL rather than PipeWire.
///
/// Three property listeners and no timer: one on the system object for the default output
/// device changing, and two on the device itself for its volume and its mute. The device's
/// pair are re-registered on the device that is current, because a listener is per object and
/// a new default device is a new object. Every callback is delivered on the main queue, which
/// is what `AudioObjectAddPropertyListenerBlock` takes a queue for.
///
/// `state` is nil while there is no output device at all — a Mac with its only device gone —
/// and the widget is then not listed.
final class AudioProvider: BarProvider {

    struct State: Equatable {
        /// 0 to 1, the device's virtual main volume — what the volume keys move.
        var volume: Double
        var muted: Bool
        /// A headphone jack or a pair of AirPods: drawn as headphones whatever the volume,
        /// as upstream's `isHeadphones` does from the sink's name.
        var headphones: Bool
    }

    private(set) var state: State?
    var onChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var defaultListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private static let defaultDevice = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static let volume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static let mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static let transport = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static let dataSource = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDataSource,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static let name = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard defaultListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceChanged() }
        var address = Self.defaultDevice
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                            .main, listener)
        defaultListener = listener
        deviceChanged()
    }

    func stop() {
        if let defaultListener {
            var address = Self.defaultDevice
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                                   .main, defaultListener)
            self.defaultListener = nil
        }
        unwatchDevice()
        device = AudioObjectID(kAudioObjectUnknown)
        state = nil
    }

    // MARK: - Clicks

    /// Right click: `toggleAllMuted`.
    func toggleMute() {
        guard device != kAudioObjectUnknown, let state else { return }
        var value: UInt32 = state.muted ? 0 : 1
        var address = Self.mute
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// The wheel: 5% a notch, as upstream's `wheelSteps × 0.05`, clamped.
    func adjustVolume(steps: Int) {
        guard let state, steps != 0 else { return }
        setVolume(state.volume + Double(steps) * 0.05)
    }

    /// The panel's slider: the output volume outright, clamped. The device's own listener
    /// reports the value back, which is what redraws the widget and the panel.
    func setVolume(_ volume: Double) {
        guard device != kAudioObjectUnknown else { return }
        var value = Float32(max(0, min(1, volume)))
        var address = Self.volume
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    // MARK: - Reading

    private func deviceChanged() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.defaultDevice
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                0, nil, &size, &id)
        if status != noErr { id = AudioObjectID(kAudioObjectUnknown) }
        if id != device {
            unwatchDevice()
            device = id
            watchDevice()
        }
        read()
    }

    private func watchDevice() {
        guard device != kAudioObjectUnknown else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read() }
        for var address in [Self.volume, Self.mute] {
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
        deviceListener = listener
    }

    private func unwatchDevice() {
        guard device != kAudioObjectUnknown, let deviceListener else { return }
        for var address in [Self.volume, Self.mute] {
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceListener)
        }
        self.deviceListener = nil
    }

    private func read() {
        let before = state
        defer { if state != before { onChange?() } }
        guard device != kAudioObjectUnknown else {
            state = nil
            return
        }
        var volume: Float32 = 0
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.volume
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) != noErr { volume = 0 }
        size = UInt32(MemoryLayout<UInt32>.size)
        address = Self.mute
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) != noErr { muted = 0 }
        state = State(volume: Double(volume), muted: muted != 0, headphones: isHeadphones())
    }

    /// Upstream matches the sink's name and description against "headphone", "headset",
    /// "earphone" and "airpod". The same words against the device's name, and two things a Mac
    /// can say outright: a built-in device whose data source is the headphone jack (`'hdpn'`),
    /// and a Bluetooth device — which on a Mac is a pair of AirPods or a headset nine times in
    /// ten, and a speaker the tenth, which the name then still has a say over.
    private func isHeadphones() -> Bool {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.transport
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr {
            if transport == kAudioDeviceTransportTypeBuiltIn {
                var source: UInt32 = 0
                size = UInt32(MemoryLayout<UInt32>.size)
                address = Self.dataSource
                if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr,
                   source == 0x6864706E /* 'hdpn' */ {
                    return true
                }
            }
        }
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address = Self.name
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let text = name?.takeRetainedValue() as String?
        else { return false }
        let lower = text.lowercased()
        return ["headphone", "headset", "earphone", "airpod"].contains { lower.contains($0) }
    }
}
