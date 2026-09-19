import AppKit
import ToeCore

/// The bar on every display: one `BarPanel` per `NSScreen`, kept in step with the displays and
/// with whether the bar is meant to be on screen at all.
///
/// Three things decide whether a panel shows, and they are kept apart because they change on
/// different occasions. `enabled` is `[bar] enabled`, the config; `hidden` is `bar toggle`, the
/// session; and a display with a native-fullscreen window in front has no bar on it whatever
/// the other two say (that last one arrives in a later step of #171). `refresh` is the one
/// place the three are combined.
final class BarWindowSet {

    private var panels: [CGDirectDisplayID: BarPanel] = [:]
    private var snapshot: BarSnapshot?
    /// `[bar] enabled`.
    var enabled = false
    /// `bar hide`: the panels are off screen and the strip is the tiles' again, until `bar show`.
    var hidden = false
    /// Hands every panel's clicks to one handler, with the display they came from.
    var onClick: ((CGDirectDisplayID, BarItem.Kind?, BarView.Button) -> Void)?
    /// The wheel, in whole notches — see `BarView.scrollWheel`.
    var onScroll: ((BarItem.Kind?, Int) -> Void)?

    /// How tall the strip is on `screen`: the configured height, or the safe area on a display
    /// with a notch.
    ///
    /// A built-in display with a `safeAreaInsets.top` keeps that strip out of `visibleFrame`
    /// whether or not the menu bar is hidden — measured for #171: 32 pt, with the menu bar
    /// showing or not — so a 26-point bar there would leave six points of wallpaper between
    /// itself and the tiles. The bar takes the strip it is given, and the slots scale with it as
    /// they would with a taller `[bar] height`.
    func height(on screen: NSScreen, metrics: BarMetrics) -> Double {
        max(metrics.height, Double(screen.safeAreaInsets.top))
    }

    /// Where the centre section is centred on `screen`, in the panel's own coordinates, or nil
    /// for the middle of the bar.
    ///
    /// The middle of a notched display is the notch, and a clock under the camera housing is a
    /// clock nobody can see — the framebuffer has it, the glass does not. So the centre section
    /// centres on one of the two gaps beside it. The right one: the two are the same width on
    /// every notched Mac so far (771.5 pt each at this display's scale), and to the right is
    /// where the Mac has always kept its clock, so the eye that goes there finds it. The choice
    /// is made from the geometry alone, not from what the sections hold, so the clock does not
    /// move as workspaces come and go.
    func centre(on screen: NSScreen) -> Double? {
        guard screen.safeAreaInsets.top > 0, let gap = screen.auxiliaryTopRightArea else { return nil }
        return Double(gap.midX - screen.frame.minX)
    }

    /// Draws `snapshot` on every display, creating panels for screens that have none and
    /// dropping the ones whose screen has gone. Called on every `refreshStatus` — cheap when
    /// nothing changed, since a panel whose snapshot is equal is not redrawn.
    func update(_ snapshot: BarSnapshot) {
        let changed = snapshot != self.snapshot
        self.snapshot = snapshot
        refresh(redraw: changed)
    }

    /// The displays changed shape or number: re-frame every panel against the new screens.
    func screensChanged() {
        refresh(redraw: true)
    }

    /// Applies `enabled` and `hidden` against the current screens.
    func refresh(redraw: Bool = true) {
        guard enabled, !hidden, let snapshot else {
            for panel in panels.values { panel.hide() }
            return
        }
        let screens = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.displayID, $0) })
        for id in panels.keys where screens[id] == nil {
            panels[id]?.hide()
            panels.removeValue(forKey: id)
        }
        for (id, screen) in screens {
            let panel = panels[id] ?? make(for: screen)
            let height = height(on: screen, metrics: snapshot.metrics)
            if redraw || !panel.panel.isVisible {
                panel.show(on: screen, height: height, centre: centre(on: screen), snapshot: snapshot)
            }
        }
    }

    private func make(for screen: NSScreen) -> BarPanel {
        let panel = BarPanel(screen: screen)
        let id = screen.displayID
        panel.onClick = { [weak self] kind, button in self?.onClick?(id, kind, button) }
        panel.onScroll = { [weak self] kind, steps in self?.onScroll?(kind, steps) }
        panels[id] = panel
        return panel
    }
}
