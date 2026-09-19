import Foundation
import IOKit.ps
import ToeCore

/// The battery, from IOKit's power sources — Omarchy's `omarchy.power`, read from
/// `IOPSCopyPowerSourcesInfo` rather than UPower.
///
/// Event-driven: `IOPSNotificationCreateRunLoopSource` fires on every change to the power
/// sources — a percent, the charger going in or out, a battery being charged — so nothing here
/// polls. A machine with no internal battery reports `state` nil, and the widget is not listed
/// at all, which is what a desktop's bar looks like upstream too.
final class PowerProvider: BarProvider {

    struct State: Equatable {
        var fraction: Double
        var onMains: Bool
        var charging: Bool
        var charged: Bool
    }

    /// nil until read, and nil on a machine without a battery.
    private(set) var state: State?
    var onChange: (() -> Void)?

    private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        read()
        // The callback is a C function pointer and cannot capture, so `self` travels as the
        // context pointer — unretained, because `stop` removes the source before the provider
        // can go away, and the Coordinator holds it for the life of the process anyway.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let provider = Unmanaged<PowerProvider>.fromOpaque(context).takeUnretainedValue()
            provider.changed()
        }, context)?.takeRetainedValue() else {
            Log.error("power: could not watch the power sources")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = nil
    }

    private func changed() {
        let before = state
        read()
        if state != before { onChange?() }
    }

    private func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            state = nil
            return
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let max = description[kIOPSMaxCapacityKey] as? Double, max > 0
            else { continue }
            state = State(
                fraction: current / max,
                onMains: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                charged: description[kIOPSIsChargedKey] as? Bool ?? false)
            return
        }
        state = nil
    }
}
