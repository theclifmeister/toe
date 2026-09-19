import Foundation
import ToeCore

/// The clock's tick: once a minute, on the minute, and once a second only while the label
/// prints seconds.
///
/// Omarchy's `SystemClock` has the same two precisions for the same reason — a repaint a second
/// is a price only the formats that show seconds pay. The timer is re-armed from the current
/// time on every fire rather than repeating, so the label changes on the minute boundary
/// instead of some fixed offset after launch drifting past it.
final class ClockProvider {

    /// Called on the main queue every time the label may have changed.
    var onTick: (() -> Void)?

    private var timer: Timer?
    private var seconds = false

    /// (Re)arms for `format`: the interval follows whether it shows seconds.
    func start(format: String) {
        seconds = ClockFormat.needsSeconds(format)
        arm()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func arm() {
        timer?.invalidate()
        let unit: TimeInterval = seconds ? 1 : 60
        let now = Date().timeIntervalSince1970
        // The next boundary, plus a hair so the tick lands after the minute has turned rather
        // than a rounding error before it.
        let next = (now / unit).rounded(.down) * unit + unit + 0.02
        let timer = Timer(fire: Date(timeIntervalSince1970: next), interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.onTick?()
            self.arm()
        }
        // `.common`, so the clock keeps time while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
