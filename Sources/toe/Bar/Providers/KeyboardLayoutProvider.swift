import Carbon
import Foundation
import ToeCore

/// The keyboard layout in use, from Text Input Services — Omarchy's `omarchy.keyboard-layout`,
/// read from `TISCopyCurrentKeyboardInputSource` rather than `hyprctl devices`.
///
/// Shown only with more than one layout to choose from, as upstream: on the single-layout
/// install most people run there is nothing to read and nothing to switch. The list is the
/// enabled, selectable keyboard input sources — layouts and input methods both, since a
/// Japanese input mode is as much a thing to switch to as a German layout — and the
/// notifications are TIS's own two, posted on the distributed centre when the selection or the
/// enabled set changes. No polling.
///
/// The label is `BarWidgets.keyboardLabel` of the source's first language — `EN`, `DE` — which
/// is the nearest thing a Mac has to xkb's brief; the localized name is the tooltip.
final class KeyboardLayoutProvider: BarProvider {

    struct State: Equatable {
        var label: String
        var name: String
    }

    /// nil with one layout or none: not listed.
    private(set) var state: State?
    var onChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let centre = DistributedNotificationCenter.default()
        for name in [kTISNotifySelectedKeyboardInputSourceChanged as String,
                     kTISNotifyEnabledKeyboardInputSourcesChanged as String] {
            observers.append(centre.addObserver(forName: Notification.Name(name), object: nil,
                                                queue: .main) { [weak self] _ in self?.read() })
        }
        read()
    }

    func stop() {
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers = []
        state = nil
    }

    /// Left click: the next layout in the system's order, wrapping — `cycleLayout`.
    func selectNext() {
        let sources = Self.selectable()
        guard sources.count > 1,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let at = sources.firstIndex(where: { Self.id($0) == Self.id(current) })
        else { return }
        TISSelectInputSource(sources[(at + 1) % sources.count])
    }

    // MARK: - Reading

    private func read() {
        let before = state
        defer { if state != before { onChange?() } }
        let sources = Self.selectable()
        guard sources.count > 1,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else {
            state = nil
            return
        }
        let name = Self.string(current, kTISPropertyLocalizedName) ?? ""
        let languages = Self.property(current, kTISPropertyInputSourceLanguages) as? [String] ?? []
        let brief = languages.first ?? name
        state = State(label: BarWidgets.keyboardLabel(brief), name: name)
    }

    /// The keyboard input sources a user can switch to: enabled, selectable, and of the
    /// keyboard category — which leaves out the palettes and the pressed-key display that
    /// TIS also calls input sources.
    private static func selectable() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceIsEnabled as String: true,
                      kTISPropertyInputSourceIsSelectCapable as String: true,
                      kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    private static func id(_ source: TISInputSource) -> String {
        string(source, kTISPropertyInputSourceID) ?? ""
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        property(source, key) as? String
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }
}
