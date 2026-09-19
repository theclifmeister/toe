import Foundation

/// A widget's eyes and ears: something in `toe` that reads one piece of the machine's state
/// for the bar and says when it changed.
///
/// Each provider keeps the last thing the system told it and calls `onChange` on the main
/// queue when that differs, which is what `Coordinator.refreshBar` waits for; the glyph it
/// then draws is `BarWidgets`' decision from the numbers, in ToeCore. The rule for the event
/// source, from #171: a listener where one exists, and no polling where one does — CoreAudio
/// property listeners, IOKit's power-source run loop source, CoreWLAN's event delegate, the
/// Text Input Services notifications, and Darwin notify for power assertions. The clock is the
/// one on a timer, and only because time has no listener.
protocol BarProvider: AnyObject {
    /// Called on the main queue whenever what the provider would draw may have changed.
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
}
