import Foundation

/// The audio panel — `panels/audio/Panel.qml`, on CoreAudio rather than PipeWire.
///
/// Upstream is a hero with a mute switch, the output slider and its devices, the input slider
/// and its devices, and a per-application mixer. The mixer is gone: a Mac has no public way to
/// list which applications are playing, let alone turn one down. The rest is here, and the
/// devices are what `kAudioHardwarePropertyDevices` lists with a stream in the right
/// direction. The hero's switch is the output's mute — upstream mutes output and input
/// together, which on a Mac would silence a call's microphone from a widget that draws a
/// speaker; the input has its own slider with its own Return.
public enum AudioPanel {

    /// How a device is attached, from `kAudioDevicePropertyTransportType`, reduced to what the
    /// glyph rule needs.
    public enum Transport: Equatable, Sendable {
        case builtIn, bluetooth, display, usb, airPlay, other
    }

    public struct Device: Equatable, Sendable {
        /// The `AudioObjectID`, which is what `PanelAction.pickOutput` carries back.
        public var id: UInt32
        public var name: String
        public var transport: Transport
        /// Built in, and its data source is the headphone jack — `'hdpn'`, the one thing a
        /// Mac says outright about headphones.
        public var jack: Bool

        public init(id: UInt32, name: String, transport: Transport = .other, jack: Bool = false) {
            self.id = id
            self.name = name
            self.transport = transport
            self.jack = jack
        }
    }

    /// What `AudioProvider` reads: the default output's volume and mute, the default input's,
    /// and the two device lists with the defaults marked.
    public struct State: Equatable, Sendable {
        public var volume: Double
        public var muted: Bool
        public var outputs: [Device]
        public var defaultOutput: UInt32?
        /// nil when there is no input device at all, which a Mac Studio with nothing plugged
        /// in is; the input section is then left out, as upstream leaves it out with no source.
        public var inputVolume: Double?
        public var inputMuted: Bool
        public var inputs: [Device]
        public var defaultInput: UInt32?

        public init(volume: Double, muted: Bool, outputs: [Device] = [], defaultOutput: UInt32? = nil,
                    inputVolume: Double? = nil, inputMuted: Bool = false, inputs: [Device] = [],
                    defaultInput: UInt32? = nil) {
            self.volume = volume
            self.muted = muted
            self.outputs = outputs
            self.defaultOutput = defaultOutput
            self.inputVolume = inputVolume
            self.inputMuted = inputMuted
            self.inputs = inputs
            self.defaultInput = defaultInput
        }

        /// Whether the default output is headphones — the widget's rule, from `isHeadphones`.
        public var headphones: Bool {
            outputs.first { $0.id == defaultOutput }.map(AudioPanel.isHeadphones) ?? false
        }
    }

    /// `isHeadphones`: the words upstream matches the sink's name against, plus the two things
    /// a Mac says outright — the headphone jack, and Bluetooth, which is a pair of AirPods or
    /// a headset nine times in ten, and a speaker the tenth, which the name then still has a
    /// say over.
    public static func isHeadphones(_ d: Device) -> Bool {
        if d.jack { return true }
        let lower = d.name.lowercased()
        if ["headphone", "headset", "earbud", "earphone", "airpod"].contains(where: lower.contains) { return true }
        if d.transport == .bluetooth {
            return !["speaker", "soundbar", "hifi", "hi-fi"].contains(where: lower.contains)
        }
        return false
    }

    /// `sinkGlyph`: headphones before anything, Bluetooth, a display's speakers, a speaker.
    public static func outputGlyph(_ d: Device) -> String {
        if isHeadphones(d) { return Glyphs.headphones }
        switch d.transport {
        case .bluetooth: return Glyphs.bluetoothOn
        case .display:   return Glyphs.monitor
        default:         return Glyphs.speaker
        }
    }

    /// `sourceGlyph`: a headset, Bluetooth, a camera's microphone, a microphone.
    public static func inputGlyph(_ d: Device) -> String {
        let lower = d.name.lowercased()
        if lower.contains("headset") || d.jack { return Glyphs.headphones }
        if d.transport == .bluetooth { return Glyphs.bluetoothOn }
        if lower.contains("webcam") || lower.contains("camera") || lower.contains("facetime") { return Glyphs.camera }
        return Glyphs.microphone
    }

    /// `outputVolumeName`: the status line's word for a volume, upstream's own.
    public static func volumeName(_ volume: Double, muted: Bool) -> String {
        if muted { return "Muted" }
        let p = Int((max(0, min(1, volume)) * 100).rounded())
        if p == 0 { return "Silenced" }
        if p >= 100 { return "Concert hall" }
        if p >= 85 { return "Party mode" }
        if p >= 70 { return "Cranked up" }
        if p >= 50 { return "Steady groove" }
        if p >= 30 { return "Easy listening" }
        if p >= 15 { return "Murmur" }
        return "Whisper"
    }

    /// `outputIcon`, the widget's rule, for the hero.
    public static func heroGlyph(_ s: State) -> String {
        if s.headphones { return Glyphs.headphones }
        if s.muted || s.volume <= 0 { return Glyphs.muted }
        if s.volume >= 0.67 { return Glyphs.volume[2] }
        if s.volume >= 0.34 { return Glyphs.volume[1] }
        return Glyphs.volume[0]
    }

    private static func percent(_ v: Double) -> String {
        "\(Int((max(0, min(1, v)) * 100).rounded()))%"
    }

    public static func rows(_ s: State) -> [PanelRow] {
        var rows: [PanelRow] = [
            .hero(glyph: heroGlyph(s), title: "Audio", status: volumeName(s.volume, muted: s.muted),
                  trailing: .toggle(on: !s.muted), action: .toggleOutputMute),
            .separator,
            .header("Output", trailing: percent(s.volume)),
            .slider(.outputVolume, value: s.volume, dimmed: s.muted, action: .toggleOutputMute),
        ]
        rows += s.outputs.map { d in
            .pick(glyph: outputGlyph(d), label: d.name, current: d.id == s.defaultOutput, action: .pickOutput(d.id))
        }
        if let inputVolume = s.inputVolume {
            rows += [
                .separator,
                .header("Input", trailing: percent(inputVolume)),
                .slider(.inputVolume, value: inputVolume, dimmed: s.inputMuted, action: .toggleInputMute),
            ]
            rows += s.inputs.map { d in
                .pick(glyph: inputGlyph(d), label: d.name, current: d.id == s.defaultInput, action: .pickInput(d.id))
            }
        }
        rows += [.separator, .settings(.sound)]
        return rows
    }
}
