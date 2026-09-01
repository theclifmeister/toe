import AppKit
import ToeCore

/// Owns the quick menu: builds its tree when it opens, feeds it keystrokes, and hands finished
/// actions back to `Coordinator`. The only place `NSEvent` meets `MenuKey`.
final class QuickMenuController: NSObject, NSWindowDelegate {

    /// Everything the tree is built from, gathered afresh on every open.
    var contextProvider: (() -> MenuContext)?
    /// The window to give focus back to on a dismissal that did nothing.
    var focusProvider: (() -> WindowID?)?
    /// The usable area of the display with focus, in AX coordinates.
    var monitorProvider: (() -> Box?)?
    var onPerform: ((MenuAction) -> Void)?
    var onRestoreFocus: ((WindowID?) -> Void)?
    var onOpenChanged: ((Bool) -> Void)?

    private(set) var isOpen = false

    private let view = QuickMenuView()
    private lazy var chrome = QuickMenuChrome(contentView: view)
    private var state: MenuState?
    private var border = BorderConfig()

    /// Captured before activating, because afterwards `frontmostApplication` is toe.
    private var previousApp: NSRunningApplication?
    private var previousWindow: WindowID?
    /// Activating another app during `perform` fires `windowDidResignKey` synchronously, so the
    /// close path has to be reentrancy-safe.
    private var isClosing = false

    override init() {
        super.init()
        view.onKey = { [weak self] event in self?.handle(event) }
        chrome.panel.delegate = self
        chrome.apply(border)
    }

    func applyStyle(_ config: BorderConfig) {
        border = config
        chrome.apply(config)
        view.accent = chrome.accent
        if isOpen { relayout() }
    }

    // MARK: - Opening and closing

    func toggle() {
        if isOpen {
            close(restoreFocus: true)
        } else {
            open()
        }
    }

    private func open() {
        guard let context = contextProvider?() else { return }
        let root = MenuTree.root(context)
        let usable = monitorProvider?() ?? Box(x: 0, y: 0, w: 1280, h: 800)
        state = MenuState(root: root,
                          visibleRows: QuickMenuGeometry.visibleRows(
                              maxHeight: min(QuickMenuGeometry.maxHeight, usable.h * 0.7)))

        previousApp = NSWorkspace.shared.frontmostApplication
        previousWindow = focusProvider?()
        isOpen = true
        onOpenChanged?(true)

        view.state = state
        view.accent = chrome.accent
        relayout()

        // The whole failure mode of this feature is "nothing happened", so say so when it opens.
        Log.info("quick menu opened: \(state?.rows.count ?? 0) row(s)")

        // Present on the next turn of the main queue, so the Carbon hotkey handler in
        // `HotkeyManager` has returned before the panel takes the keyboard.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen else { return }
            NSApp.activate()
            self.chrome.panel.makeKeyAndOrderFront(nil)
            // Without this the panel itself is first responder, and `NSWindow`'s keyDown routes to
            // the field editor rather than to the view.
            self.chrome.panel.makeFirstResponder(self.view)
            self.verifyKeyness(attempt: 0)
        }
    }

    /// toe is an `.accessory` app, which may activate itself — but macOS's cooperative activation
    /// can *deny* a non-active app activation unless it can attribute recent user input to it. A
    /// Carbon hotkey press is delivered to toe's own event target and does count, so this succeeds
    /// in practice; it is simply not contractual, and the failure mode is the bad one — a visible
    /// menu that is not key, with every keystroke going into whatever the user was editing. So
    /// check, retry twice, and then close rather than swallow.
    private func verifyKeyness(attempt: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen, !self.chrome.panel.isKeyWindow else { return }
            guard attempt < 2 else {
                Log.error("quick menu could not take the keyboard; closing rather than swallowing keys")
                self.close(restoreFocus: true)
                return
            }
            NSApp.activate()
            self.chrome.panel.makeKeyAndOrderFront(nil)
            self.verifyKeyness(attempt: attempt + 1)
        }
    }

    /// `restoreFocus` is for a dismissal that did nothing — Esc at the root, a toggle, a failure to
    /// take the keyboard. When a row *has* acted, the action decides where focus goes: putting the
    /// old window back and then switching workspaces would only fight itself.
    private func close(restoreFocus: Bool) {
        guard isOpen, !isClosing else { return }
        isClosing = true
        isOpen = false
        state = nil
        view.state = nil
        chrome.panel.orderOut(nil)
        onOpenChanged?(false)
        if restoreFocus {
            if previousWindow != nil {
                onRestoreFocus?(previousWindow)
            } else {
                // Nothing toe manages had focus — the Finder desktop, say. Hand activation back to
                // whichever app it was, rather than letting macOS pick the next one in its own order.
                previousApp?.activate()
            }
        }
        previousApp = nil
        previousWindow = nil
        isClosing = false
    }

    /// Clicking another app, or anything else taking the keyboard, dismisses without restoring
    /// focus: whoever took it is where the user wants to be. Not `hidesOnDeactivate`, which hides
    /// the window behind our back without any of this running.
    func windowDidResignKey(_ notification: Notification) {
        guard isOpen, !isClosing else { return }
        close(restoreFocus: false)
    }

    /// The status item's `NSMenu` blocks the run loop while it tracks, so it must not open over a
    /// live key panel.
    func closeForStatusMenu() {
        close(restoreFocus: false)
    }

    // MARK: - Keys

    private func handle(_ event: NSEvent) {
        guard isOpen, var state else { return }
        let modifiers = Modifiers(event.modifierFlags)
        guard let key = MenuKey.from(keyCode: UInt32(event.keyCode),
                                     characters: event.charactersIgnoringModifiers ?? "",
                                     modifiers: modifiers) else { return }

        let outcome = state.handle(key)
        self.state = state
        view.state = state

        switch outcome {
        case .ignored:
            break
        case .redraw:
            relayout()
            view.announceSelection()
        case .dismiss:
            close(restoreFocus: true)
        case .perform(let action):
            perform(action)
        }
    }

    private func perform(_ action: MenuAction) {
        // A system action that needs asking about becomes a level rather than a dialog — a
        // hierarchical menu already knows how to ask a question.
        if case .system(let system) = action, system.needsConfirmation {
            state?.push(title: system.confirmationVerb, items: MenuTree.confirmation(system))
            view.state = state
            relayout()
            return
        }
        close(restoreFocus: false)
        onPerform?(action)
    }

    // MARK: - Geometry

    private func relayout() {
        guard let state else { return }
        let usable = monitorProvider?() ?? Box(x: 0, y: 0, w: 1280, h: 800)
        let visible = min(state.rows.count, state.visibleRows)
        let frame = QuickMenuGeometry.frame(rowCount: max(1, visible), on: usable)
        chrome.setFrame(frame, contentView: view)
        view.needsDisplay = true
    }
}

extension Modifiers {
    /// ToeCore keeps its own Carbon-flavoured modifier set so it needs no AppKit; this is the
    /// one place the two meet.
    init(_ flags: NSEvent.ModifierFlags) {
        var result: Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        self = result
    }
}
