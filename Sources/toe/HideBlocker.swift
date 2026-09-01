import AppKit

/// Puts back any application that gets hidden.
///
/// `⌘H` and `⌘⌥H` take an application's windows out of the layout without closing them: the tree
/// reflows around the gap, and there is nothing on screen to say where they went or how to get
/// them back — `SUPER`+arrows cannot reach a hidden window, because it is not on any workspace any
/// more. Omarchy has no equivalent, so the honest behaviour is for hiding not to happen.
///
/// Deliberately a notification rather than a keyboard event tap: hiding is *observable*, so toe
/// can undo it without watching a single keystroke. That also catches the routes a shortcut tap
/// would miss — the Dock's Hide menu item, an app hiding itself, and `⌘⌥H` hiding everything else
/// at once, which arrives as one notification per application.
///
/// Undoing a hide is not just `unhide()`. macOS drops the frontmost application on the way in and
/// does not give it back on the way out, so the app returns with nothing focused; and because its
/// windows kept the frames they had, toe's own bookkeeping still believes they are placed
/// correctly and writes nothing. Both have to be put right once the app is actually back, which is
/// what `onRestored` is for.
final class HideBlocker {

    /// Fires when an application toe unhid is back on screen, having already been re-activated.
    var onRestored: ((pid_t) -> Void)?

    private var observers: [any NSObjectProtocol] = []
    /// The applications toe is in the middle of putting back. An unhide toe did not ask for — the
    /// user picking the app out of the Dock — must be left entirely alone.
    private var pending: Set<pid_t> = []
    private var unhidden = 0

    var isRunning: Bool { !observers.isEmpty }

    deinit { stop() }

    func start() {
        guard observers.isEmpty else { return }

        observe(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            guard let self else { return }
            self.pending.insert(app.processIdentifier)
            // The notification arrives after the hide, so this is an undo rather than a veto: the
            // windows are gone for a frame before they come back.
            app.unhide()
            if self.unhidden == 0 { Log.info("hide blocker: unhiding applications as they are hidden") }
            self.unhidden &+= 1
        }

        observe(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            guard let self, self.pending.remove(app.processIdentifier) != nil else { return }
            // Hiding took the frontmost application away; unhiding does not hand it back.
            app.activate()
            self.onRestored?(app.processIdentifier)
        }

        Log.info("hide blocker: active")
    }

    func stop() {
        guard !observers.isEmpty else { return }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        pending.removeAll()
        unhidden = 0
        Log.info("hide blocker: stopped")
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping (NSRunningApplication) -> Void) {
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            handler(app)
        }
        observers.append(observer)
    }
}
