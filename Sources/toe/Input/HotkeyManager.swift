import AppKit
import Carbon.HIToolbox
import ToeCore

/// Global hotkeys via Carbon's `RegisterEventHotKey`.
///
/// Deliberately not a `CGEventTap`: a tap would receive every keystroke you type, which is
/// far more access than a window manager needs. Carbon hotkeys only ever deliver the exact
/// combinations toe registers, and they need no permission beyond the Accessibility grant
/// that moving windows already requires.
final class HotkeyManager {

    var onTrigger: ((Binding) -> Void)?

    private static let signature: OSType = 0x746F_6521   // 'toe!'
    private static weak var shared: HotkeyManager?

    private var handler: EventHandlerRef?
    private var registered: [UInt32: (ref: EventHotKeyRef, binding: Binding)] = [:]
    private var nextID: UInt32 = 1

    init() {
        HotkeyManager.shared = self
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            HotkeyManager.shared?.fire(id: hotKeyID.id)
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func fire(id: UInt32) {
        guard let binding = registered[id]?.binding else { return }
        onTrigger?(binding)
    }

    /// Replaces every registration. Returns the bindings that the system refused, which
    /// happens when another app already owns the combination.
    @discardableResult
    func register(_ bindings: [Binding]) -> [Binding] {
        unregisterAll()
        var rejected: [Binding] = []

        for binding in bindings {
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: id)
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers.rawValue,
                                             hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[id] = (ref, binding)
            } else {
                rejected.append(binding)
            }
        }
        return rejected
    }

    func unregisterAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }
}
