import Foundation
import IOKit
import IOKit.ps
import ToeCore

/// The battery, from IOKit's power sources — Omarchy's `omarchy.power`, read from
/// `IOPSCopyPowerSourcesInfo` rather than UPower.
///
/// Event-driven: `IOPSNotificationCreateRunLoopSource` fires on every change to the power
/// sources — a percent, the charger going in or out, a battery being charged — so nothing here
/// polls. A machine with no internal battery reports `state` nil, and the widget is not listed
/// at all, which is what a desktop's bar looks like upstream too.
///
/// The panel's stats come from the same read, plus two the power sources do not carry: the
/// cycle count and the capacities live on the `AppleSmartBattery` registry entry, read at the
/// same moments, and Low Power Mode is `ProcessInfo`'s, with its own notification.
final class PowerProvider: BarProvider {

    /// nil until read, and nil on a machine without a battery.
    private(set) var state: PowerPanel.Battery?
    var onChange: (() -> Void)?

    private var source: CFRunLoopSource?
    private var lowPowerObserver: (any NSObjectProtocol)?

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
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.changed()
        }
    }

    func stop() {
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
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
            // −1 is IOKit's "not yet known", which it says for a minute after every plug or
            // unplug; the panel prints "Calculating…" for nil.
            func minutes(_ key: String) -> Int? {
                guard let value = description[key] as? Int, value >= 0 else { return nil }
                return value
            }
            let registry = Self.smartBattery()
            state = PowerPanel.Battery(
                fraction: current / max,
                onMains: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                charged: description[kIOPSIsChargedKey] as? Bool ?? false,
                minutesToEmpty: minutes(kIOPSTimeToEmptyKey),
                minutesToFull: minutes(kIOPSTimeToFullChargeKey),
                health: description[kIOPSBatteryHealthKey] as? String,
                cycleCount: registry.cycles,
                maximumCapacity: registry.maximumCapacity,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
            return
        }
        state = nil
    }

    /// The cycle count and the capacity ratio off the `AppleSmartBattery` entry — public IOKit
    /// registry reads, no permission, and the entry exists on every Mac with a battery.
    /// `CycleCount` is at the top; the capacities moved: an Intel Mac has `AppleRawMaxCapacity`
    /// and `DesignCapacity` at the top level, and on Apple silicon (measured on macOS 27 for
    /// #177) they are `FullChargeCapacity` and `DesignCapacity` inside the `BatteryData`
    /// dictionary, with nothing at the top but a `MaxCapacity` of 100 that means nothing. The
    /// ratio is what System Settings prints as Maximum Capacity.
    private static func smartBattery() -> (cycles: Int?, maximumCapacity: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let data = property("BatteryData") as? [String: Any] ?? [:]
        func number(_ key: String) -> Int? {
            (property(key) as? Int) ?? (data[key] as? Int)
        }
        let cycles = number("CycleCount")
        var maximum: Int?
        if let full = number("AppleRawMaxCapacity") ?? number("FullChargeCapacity"),
           let design = number("DesignCapacity"), design > 0 {
            // A fresh battery reads a hair over its design, and 101% is not a number System
            // Settings would print.
            maximum = min(100, Int((Double(full) / Double(design) * 100).rounded()))
        }
        return (cycles, maximum)
    }
}
