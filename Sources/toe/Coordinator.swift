import AppKit
import ApplicationServices
import ToeCore

/// Wires the layout engine to the screen: window events in, frames and focus out.
final class Coordinator: WindowTrackerDelegate {

    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/toe/" + Config.fileName)

    private let workspaces = WorkspaceManager()
    private let tracker = WindowTracker()
    private let hotkeys = HotkeyManager()
    private let border = BorderOverlay()
    private let drag = DragMonitor()
    private let dockSwipes = DockSwipeTap()
    private let snapshot = ScreenSnapshot()
    private let slide = SlideOverlay()
    private let hideBlocker = HideBlocker()
    private let status = StatusItem()
    private let quickMenu = QuickMenu()
    private var watcher: ConfigWatcher?
    /// Watches `~/.config/toe/themes`, so a theme folder appearing or going away is noticed
    /// without waiting for anything else to happen. Optional and re-checked on every reload,
    /// because that directory need not exist — most installs never make one.
    private var themeWatcher: ConfigWatcher?
    /// Watches the *current* theme's `colors.toml`, the one file whose contents can change what
    /// is on screen. Two watchers rather than one because a write inside `themes/rose-pine/` is
    /// not a write to `themes/` — directory notifications do not travel up — and one watcher per
    /// installed theme would mean ninety file descriptors to catch edits to eighty-nine palettes
    /// nothing is drawing with.
    private var paletteWatcher: ConfigWatcher?
    private var watchedPalette: String?

    /// Every theme toe can see: the three it ships, merged with whatever is in the themes
    /// directory. Rebuilt on every reload *and* every time the menu opens, which is what makes a
    /// folder created a moment ago show up without a reload.
    private var themes: [ThemeRef] = []
    /// What Omarchy publishes and this machine has not got. Fetched lazily — see `ThemeCatalogue`.
    private let available = ThemeCatalogue()
    /// What a download is doing. Separate from `warnings`, which is replaced wholesale on every
    /// reload, and from `setupWarnings` and `runtimeWarnings`, which are for things that have
    /// gone wrong: this is progress, and it clears itself when it finishes.
    ///
    /// One value rather than the pair of pre-built strings this used to hold. Both of those were
    /// for the menu bar — the strip and the tooltip behind it — and the menu bar has stopped
    /// saying anything about a download: the quick menu fills the row instead, and a row wants
    /// the numbers, not a sentence. It doubles as the one-download-at-a-time latch.
    private var downloading: ThemeDownload?
    /// The current theme's pictures, in cycle order, and where in that cycle we are.
    private var backgrounds: [String] = []
    private var currentBackground: String?
    /// The theme whose picture is on screen, so that changing theme puts a matching one up and a
    /// plain reload does not touch what you are looking at.
    private var pictureFrom: String?
    private let wallpaper = Wallpaper()
    /// The bytes of the config last loaded, so the same file arriving three times over — the
    /// directory write, the rename, and the reload a theme pick asks for directly — costs one
    /// reload rather than three. See `loadConfig(force:)`.
    private var loadedText: String?

    private var config = Config.makeDefault()
    private var warnings: [String] = []
    /// What the `apply*` functions found wrong the last time they ran — a tap that would not
    /// create, a permission not yet granted. Rebuilt from nothing on every reload, because a
    /// reload re-runs every one of them and the answer may have changed: `swallow_dock_swipes`
    /// switched off is a tap nobody needs any more. `applyDockSwipeSetting` runs first and
    /// starts the list afresh; the others append.
    private var setupWarnings: [String] = []
    /// Problems that are not the config's fault and that nothing in a reload knows how to
    /// re-check, so they must survive one — a theme download that failed is no more fetched
    /// after `SUPER`+`SHIFT`+`R` than before. Keyed by who put the entry there, so a writer takes
    /// back its own and nobody else's: a failed fetch is keyed by the theme's slug and comes down
    /// when a later fetch of that theme succeeds.
    ///
    /// Kept apart from `setupWarnings` on purpose. These used to be one list, and the
    /// `removeAll()` that starts the dock-tap check afresh took the download failure with it on
    /// the next config save — a message documented as surviving a reload that did not. Two
    /// lists cleared at two moments by two hands cannot repeat that.
    private var runtimeWarnings: [String: String] = [:]
    /// False until Accessibility has landed and `beginManaging()` has run. A config reload before
    /// that must not try to create the event tap: it would be refused and never retried.
    private var isManaging = false
    /// The frame each window is supposed to occupy, so a re-render does not churn every window.
    private var desired: [WindowID: Box] = [:]
    /// How many times we have re-asserted a frame an app pushed back on. Bounded, so a window
    /// with a minimum size larger than its tile is written once and then left alone rather
    /// than fought with forever.
    private var corrections: [WindowID: Int] = [:]
    private var focusApplied: WindowID?
    /// Windows toe raised itself, and when — see `isEchoOfOwnRaise`.
    private var selfRaised: [WindowID: TimeInterval] = [:]
    /// How long a focus notification can still be the echo of one of those raises.
    ///
    /// Generous, because the cost of getting this wrong runs the two ways round very
    /// differently. An echo let through is recorded as a focus change that never happened, and
    /// toe then works from a window the user is not on — `movefocus` walks from the wrong
    /// place, and the border sits on the wrong window until something corrects it. A click let
    /// through late is one focus change toe hears about a beat later than it might have.
    /// Applications answer a raise in milliseconds when they are idle and take their time when
    /// they are not, so this is set for the slow ones.
    private static let raiseEchoWindow: TimeInterval = 1.2
    /// True from the moment a snapshot is restored until the windows it named have had their
    /// chance to turn up. Saving is suspended meanwhile: a snapshot taken halfway through
    /// adoption would record a layout missing most of its windows, over the top of the good
    /// one.
    private var isSettlingSession = false
    /// Pending debounced write. See `scheduleSessionSave`.
    private var sessionSave: DispatchWorkItem?
    /// Pending settles, one per window. See `scheduleSettle`.
    private var settleWork: [WindowID: DispatchWorkItem] = [:]
    /// How many times in a row a window has been put back where toe wants it without it staying
    /// there. `corrections` is the same idea and is deliberately not reused: that one answers an
    /// app re-asserting its own geometry the instant it does it, so it is spent on frames that
    /// are still moving — which is exactly how macOS's edge-snap exhausts it, see `settle`. This
    /// one is spent only on frames that have already held still, and only counts so that an app
    /// which insists on its own position is left to it rather than ping-ponged with.
    private var settleAttempts: [WindowID: Int] = [:]
    /// How long a frame has to hold still before the place it landed is taken as final. Not the
    /// length of macOS's edge-snap animation but a quiet period after it: the deadline is pushed
    /// back by every notification that arrives.
    ///
    /// Measured, not reasoned about. 0.1 is too tight — macOS's edge-snap does not deliver a
    /// notification every animation frame, and the gaps in the middle of one are long enough
    /// to be taken for its end, at which point toe writes under a window that is still moving
    /// and macOS puts it back flush. The window twitches and the correction is lost, since the
    /// attempt cap counts a write that landed nowhere. 0.2 clears those gaps.
    private static let settleLatency: TimeInterval = 0.2
    /// The window the user has hold of. Its frame is theirs until they let go: toe neither
    /// re-asserts its tile nor writes it a new one, the same courtesy `apply` already extends
    /// to a floating window.
    private var draggedWindow: WindowID? { drag.isDragging ? drag.window : nil }
    /// Where a swipe's slide has got to. See `swipeToWorkspace` for the sequence and `apply`
    /// for the two phases a render from elsewhere cuts short.
    private enum SlidePhase {
        case idle
        /// The model has switched; the screen has not. Waiting for the picture of it.
        case awaitingPicture
        /// The picture is up and the switch has been made under it. Waiting for the picture of
        /// the result.
        case switching
        /// Both pictures are moving.
        case sliding
    }
    private var slidePhase = SlidePhase.idle
    /// Bumped whenever a slide is started or cancelled, so that a callback from an earlier one
    /// — a picture, a timer, an animation ending — finds it is no longer wanted and does nothing.
    private var slideGeneration = 0
    /// How long the switch waits for the first picture before going ahead without one. A
    /// capture is a few milliseconds once the capture session is warm, and the user's fingers
    /// have just left the trackpad, so this is the most a swipe may be held up for a picture.
    private static let slidePictureDeadline: TimeInterval = 0.1
    /// How long after the switch the second picture is taken. The Accessibility writes have
    /// returned by then, but that means the app has *received* its frame, not painted it —
    /// Chromium takes a frame or two — and a picture of a half-drawn window slides in as a
    /// half-drawn window. The live screen replaces it the moment the slide ends, so an app
    /// slower than this costs a glitch of one slide, not a wrong layout.
    private static let slideSettleTime: TimeInterval = 0.08
    /// How long the switch is held after the panel goes up, so the panel is on screen with its
    /// picture before anything under it moves. The picture is flushed to the render server
    /// before the panel is ordered front, but the window server composites on its own clock and
    /// a window that has been moved lands in the very next frame; two refreshes covers the one
    /// the panel is presented in and the one after, on a 60 Hz display or a faster one. Without
    /// this the switch showed through for a frame and the picture snapped back over it — a
    /// flash before the slide, which is worse than no slide.
    private static let slidePanelLatency: TimeInterval = 0.035
    private var signalSources: [any DispatchSourceSignal] = []

    // MARK: - Start-up

    func start() {
        workspaces.cursorLocation = { Coordinates.toAX(NSEvent.mouseLocation) }
        status.onSelectWorkspace = { [weak self] index in
            self?.dispatch(.workspace(.index(index)))
        }
        status.onOpenAccessibility = { Self.openAccessibilitySettings() }
        status.onOpenMenu = { [weak self] in self?.dispatch(.menu(.root)) }

        installSignalHandlers()
        // Symbolic hotkey state outlives the process, so a previous toe that was killed rather
        // than quit may have left Mission Control's shortcut switched off. Give it back before
        // anything else, so the config below decides from a known-good baseline.
        SymbolicHotkeys.repairAfterUncleanExit()
        // Same reasoning, same shape: the reveal-desktop preference is the window server's, not
        // toe's, so a copy that was killed rather than quit may have left it switched off.
        WallpaperClick.repairAfterUncleanExit()
        // And again for macOS's drag-to-edge tiling, which is two more WindowManager preferences
        // of exactly the same kind.
        EdgeTiling.repairAfterUncleanExit()
        // And the last of them: the Dock's auto-hide setting is the Dock's own, so a copy that
        // was killed rather than quit may have left the Dock hiding itself.
        DockAutoHide.repairAfterUncleanExit()
        // Not the same thing as those three — the desktop picture is not given back on the way
        // out — but the note of what was there before toe touched it is read at the same point,
        // so a theme picked in a run that was killed is still reversible in this one. See
        // `Wallpaper`.
        wallpaper.repairAfterUncleanExit()
        writeDefaultConfigIfMissing()
        loadConfig(force: true)

        // Starting and finishing both change what the Theme level says — the note row appears
        // and then gives way to the themes it was waiting for, without the menu having to be
        // closed and opened again to notice.
        available.onChange = { [weak self] in self?.refreshMenu() }

        watcher = ConfigWatcher(url: Coordinator.configURL)
        watcher?.onChange = { [weak self] in self?.loadConfig() }
        watcher?.start()

        hotkeys.onTrigger = { [weak self] binding in
            guard let self else { return }
            // A Carbon hotkey is resolved system-wide, ahead of whichever window has the
            // keyboard — including toe's own menu. That is what lets a second SUPER+SPACE close
            // the menu rather than typing a space into its filter, and it is also why everything
            // else has to be held back: SUPER+W while the menu is up would close a window the
            // user cannot see. `quit` stays live so a wedged menu can never trap anyone, which is
            // the reasoning behind `Config.fallbackBindings` as well.
            if self.quickMenu.isVisible {
                switch binding.command {
                case .menu, .quit: break
                default: return
                }
            }
            self.dispatch(binding.command)
        }
        quickMenu.onCommand = { [weak self] command in self?.dispatch(command) }
        quickMenu.onToggleSetting = { [weak self] setting in self?.toggle(setting) ?? false }
        // Dragging a tiled window over another one trades their places, live, the way
        // Hyprland's `IHyprLayout::onMouseMove` does.
        drag.onMove = { [weak self] id, point in
            // Not while an edge is in hand: the pointer is on the seam between two tiles, which
            // is to say at the neighbour's edge, and a swap there would trade the two windows
            // the user is trying to resize. For a left- or top-edge drag both Accessibility
            // notifications are queued ahead of the first `mouseDragged` the monitor sees, so
            // the promotion lands first; if it ever did not, the cost is one swap — today's
            // behaviour, not a new one.
            guard let self, self.drag.kind == .move,
                  self.workspaces.swapWithWindow(at: point, dragging: id) else { return }
            self.apply(refocus: false)
        }
        drag.onEnd = { [weak self] id, kind, origin in self?.endDrag(id, kind: kind, origin: origin) }
        hideBlocker.onRestored = { [weak self] pid in self?.relayoutAfterUnhide(pid) }
        // A sideways dock swipe is `workspace e+1` / `e-1` from the trackpad. Only while
        // `gestures.swallow_dock_swipes` is on, and no `if` here says so: `applyDockSwipeSetting`
        // stops the tap when the setting is off, so there is no event to arrive. The handler is
        // already off the tap's callback (see `DockSwipeTap.onSwipe`), so `apply()`'s AX round
        // trips are safe from here.
        dockSwipes.onSwipe = { [weak self] direction in
            guard let self else { return }
            let natural = NaturalScrolling.isOn
            let target = WorkspaceTarget.swipe(direction, naturalScrolling: natural)
            let before = self.workspaces.focusedWorkspaceIndex
            self.swipeToWorkspace(target)
            let after = self.workspaces.focusedWorkspaceIndex
            // `.next` / `.previous` walk the workspaces in use, as SUPER+TAB does, so a fresh
            // session with everything on one workspace has nowhere to go — say so, or the first
            // swipe anyone tries reads as broken.
            Log.info("dock swipe \(direction) (natural scrolling \(natural ? "on" : "off")): "
                     + (before == after ? "no other workspace in use, staying on \(before)"
                                        : "workspace \(before) → \(after)"))
        }

        guard waitForAccessibility() else {
            Log.error("no Accessibility permission — hotkeys are live but windows cannot be moved. "
                      + "Grant it in System Settings › Privacy & Security › Accessibility, "
                      + "or run `make reset-perms` after a rebuild.")
            return
        }
        beginManaging()
    }

    /// `make run` restarts toe with `pkill`, and SIGTERM's default action would leave a hidden
    /// workspace's windows parked in the stash corner. The next launch then adopts them there
    /// and records that corner as the frame to float them back to — so a window you floated
    /// would disappear. Unstash before going away, exactly as `quit` does.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutDown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// toe is useless without Accessibility, but it should not die either — it keeps its menu
    /// bar item and starts the moment the permission is granted.
    private func waitForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return true }

        refreshStatus()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            Log.info("Accessibility granted")
            self?.beginManaging()
        }
        return false
    }

    private func beginManaging() {
        // Before the first AX call: caps how long any single one can block the main thread.
        AX.setGlobalMessagingTimeout()
        isManaging = true
        tracker.delegate = self
        tracker.floatRules = config.floatRules
        refreshMonitors()
        restoreSession()
        tracker.start()
        settleSession()
        // Deliberately here and not in `start()`: a filtering event tap needs the Accessibility
        // grant, and it is refused outright — never retried — without one. This is the first
        // point at which the grant is known to exist, whether it was already there or has just
        // been given, so a first run picks the tap up without a relaunch.
        applyDockSwipeSetting()
        applyAnimationSetting()
        applyMiscSettings()
        applySessionSetting()
        refreshStatus()
        apply(refocus: false)
        Log.info("managing \(tracker.windows.count) window(s) across \(workspaces.monitors.count) monitor(s)")
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Config

    /// Writes the shipped default on first run, for this user only.
    ///
    /// This file is executable code, not merely settings: an `exec` binding runs `/bin/sh -c`
    /// with whatever it says, about 150 ms after it changes, inside a login agent holding the
    /// Accessibility grant. So the mode is set here rather than inherited from whatever umask
    /// happens to be in effect, and a failure is named rather than swallowed — a first run
    /// that could not write its config used to behave exactly like one that had, leaving you
    /// looking for a file that was never created.
    private func writeDefaultConfigIfMissing() {
        let url = Coordinator.configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            Log.error("could not create \(url.deletingLastPathComponent().path): \(error.localizedDescription)")
            return
        }

        // open with O_EXCL rather than a write through FileManager, for two reasons: it
        // refuses rather than following a symlink already sitting at that path, and it is one
        // call that both creates the file and fixes its mode, so the file never exists at the
        // umask's mode even briefly.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            Log.error("could not create \(url.path): \(String(cString: strerror(errno)))")
            return
        }
        defer { close(fd) }

        let bytes = Data(Config.defaultTOML.utf8)
        let written = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if written != bytes.count {
            Log.error("could not write \(url.path): \(String(cString: strerror(errno)))")
        }
    }

    /// Names a config file that other people can rewrite, or that belongs to someone else.
    ///
    /// A warning and not a refusal: symlinking this file into a dotfiles repository is how a
    /// good many people manage it, and refusing to load a symlink would break every one of
    /// them. `stat` rather than `lstat` for exactly that reason — what runs is the file at the
    /// end of the link, so that is the file whose permissions matter.
    private static func permissionWarning(for url: URL) -> String? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let name = url.lastPathComponent
        if info.st_uid != getuid() {
            return "\(name) belongs to uid \(info.st_uid), not to you — whoever owns it can run commands as you"
        }
        if info.st_mode & (S_IWGRP | S_IWOTH) != 0 {
            let mode = String(info.st_mode & 0o777, radix: 8)
            return "\(name) is mode \(mode), writable by other users — it runs shell commands, so chmod 600 it"
        }
        return nil
    }

    /// - Parameter force: reload even when the file has not changed. The watcher fires two or
    ///   three times for a single save — once for the directory write, once for the rename — and
    ///   a theme pick reloads directly as well as being seen by the watcher a beat later. A reload
    ///   is not free: it clears `desired` and re-writes every window's frame over Accessibility.
    ///   So the same bytes twice running are ignored, except when something asked for a reload on
    ///   purpose: `SUPER`+`SHIFT`+`R`, startup, and a palette edit, where `toe.toml` itself has
    ///   not changed at all.
    private func loadConfig(force: Bool = false) {
        let text = (try? String(contentsOf: Coordinator.configURL, encoding: .utf8)) ?? Config.defaultTOML
        guard force || text != loadedText else {
            // The bytes are the same, so there is nothing to re-apply — but the watches still
            // have to be re-checked, because *making* `~/.config/toe/themes` is a write to
            // `~/.config/toe` and changes not one byte of `toe.toml`. Returning above this line
            // is what left the themes watch unarmed until the next real config edit.
            applyThemeWatch()
            return
        }
        let newConfig: Config
        do {
            newConfig = try Config.parse(text)
        } catch {
            // Keep running on the last good config — a typo must never cost you your keyboard.
            warnings = ["\(Coordinator.configURL.lastPathComponent) \(error)"]
            loadedText = nil          // so that saving a fix always reloads, unchanged or not
            refreshStatus()
            Log.error("config error, keeping the previous config: \(error)")
            return
        }
        loadedText = text

        config = newConfig
        warnings = newConfig.warnings
        if let warning = Coordinator.permissionWarning(for: Coordinator.configURL) {
            warnings.append(warning)
        }

        // The theme is resolved between parsing and the fan-out below, because resolving a name
        // needs the disk and `Config.parse` is pure text. Everything after this point therefore
        // reads `config` and not `newConfig` — `newConfig` is the file as written, `config` is
        // the file with its theme applied, and they differ in exactly the colours. Do not tidy
        // these back to `newConfig`.
        applyTheme(to: newConfig)
        applyThemeWatch()

        let rejected = hotkeys.register(config.bindings)
        warnings += rejected.map { "\($0.source): already claimed by another app" }

        workspaces.options = config.dwindle
        workspaces.gaps = config.gaps
        workspaces.floatingSize = config.floating
        tracker.floatRules = config.floatRules
        border.apply(config.border)
        status.persistentWorkspaces = config.bar.persistentWorkspaces
        applyDockSwipeSetting()
        applyAnimationSetting()
        applyMiscSettings()
        applySessionSetting()

        refreshStatus()
        // The theme may have changed under an open menu — most often because a download just
        // finished and `setTheme` wrote it — so the row that is now `current` says so without
        // waiting for the menu to be reopened.
        refreshMenu()
        Log.info("config loaded: \(config.bindings.count) binding(s), \(warnings.count) warning(s)")
        for warning in warnings { Log.error("config: \(warning)") }
        desired.removeAll()
        corrections.removeAll()          // gaps may have changed; re-write every frame
        apply(refocus: false)
    }

    // MARK: - Themes

    /// Turns `[theme] name` into colours.
    ///
    /// The list is rebuilt here as well as at menu-open time, because it is what the unknown-name
    /// warning lists as the alternatives, and because a theme directory that appeared since the
    /// last reload should be resolvable now rather than after another one.
    private func applyTheme(to parsed: Config) {
        themes = ThemeStore.installed()

        let wanted = Slug.make(parsed.theme.name)
        if wanted.isEmpty {
            // Un-choosing the theme is the moment the picture is actually withdrawn, so it is the
            // moment it goes back — not on quit. `Wallpaper` says why at length.
            //
            // Asked of the disk rather than of `backgrounds`/`currentBackground`, which are both
            // empty on the first load of every run: pick a theme, quit, clear the name by hand,
            // start again, and an in-memory test would find nothing to give back and leave the
            // old theme's picture up for good. The memo on disk is what survives the restart.
            if BackgroundStore.load() != nil { wallpaper.restore() }
            backgrounds = []
            currentBackground = nil
            pictureFrom = nil
            BackgroundStore.clear()
            return
        }

        switch ThemeStore.theme(named: wanted) {
        case .success(let theme):
            config = parsed.applying(theme)
        case .failure(let error):
            // The name the *file* spelled goes in the warning, so the tooltip quotes the user's
            // own words back at them — but it must not survive in `config`, because
            // `config.theme.name` is joined onto a path in three places below and `Slug.make`
            // guarantees a safe path component only for the value it returns, not for the raw
            // text it was given. `name = "../evil"` slugs to `evil`, fails to resolve, and would
            // otherwise leave the raw `../evil` to be walked out of the themes directory.
            // What to suggest depends on what there is. "try " followed by nothing is what this
            // said on a machine with no themes installed — which is every machine that has not
            // downloaded one yet, and so exactly the machine most in need of being told where to
            // go. A name that is merely not downloaded yet gets told that specifically, because
            // it is a different problem from a name that is wrong.
            let advice: String
            if available.themes.contains(where: { $0.slug == wanted }) {
                advice = "Style › Theme can fetch it"
            } else if !themes.isEmpty {
                advice = "try " + themes.map(\.slug).joined(separator: ", ")
            } else {
                advice = "Style › Theme is where you get one"
            }
            warnings.append("theme.name: \(error) — \(advice)")
            config.theme.name = ""
            backgrounds = []
            currentBackground = nil
            pictureFrom = nil
            wallpaper.forget()
            return
        }

        // `applying` put the *resolved* slug here, so every path built from it below is a
        // single safe component by construction.
        backgrounds = ThemeStore.backgrounds(named: config.theme.name)
        // A remembered name that is no longer in the folder reads as nothing current, which
        // `Backgrounds.next` turns into starting from the first.
        currentBackground = BackgroundStore.load().flatMap { backgrounds.contains($0) ? $0 : nil }

        // Changing theme puts up one of the new theme's pictures, as `omarchy-theme-set` does by
        // calling `omarchy-theme-bg-next` on its way out — a theme that came with backgrounds and
        // left the old one on screen would be half-applied.
        //
        // Only when the theme actually changed, though. This runs on every reload, and re-setting
        // the picture each time would fight anyone who had cycled to another one, and would put
        // the wallpaper back every time you saved an unrelated line of your config.
        //
        // The one you had is preferred over the first, so a picture you cycled to survives a
        // restart; setting it again is what primes `Wallpaper` to catch up a Space or a display
        // that has not seen it, and costs nothing when it is already up — `reapply` reads back
        // before it writes.
        let changed = pictureFrom != config.theme.name
        pictureFrom = config.theme.name
        guard changed else { return }
        guard let picture = currentBackground ?? backgrounds.first else {
            // The new theme brings no pictures, so toe stops having an opinion about the
            // wallpaper rather than going on catching Spaces up with the last theme's.
            wallpaper.forget()
            return
        }
        setBackground(picture)
    }

    /// Arms the two theme watches, and re-points the palette one when the theme changes.
    ///
    /// Re-checked on every reload rather than only at startup, because creating
    /// `~/.config/toe/themes` is itself a write to `~/.config/toe`, which the config watcher
    /// already sees — so making the folder is enough to arm this without restarting toe.
    ///
    /// Both call `loadConfig(force:)`: neither a palette edit nor a theme folder appearing
    /// changes a byte of `toe.toml`, so the unchanged-bytes early-out would otherwise swallow
    /// them both.
    private func applyThemeWatch() {
        themeWatcher = watch(ThemeStore.directory, existing: themeWatcher)

        // The current theme only. Its palette is the one whose edits can change what is on
        // screen; the rest are edits to colours nothing is drawing with.
        // Re-pointed when the theme changes, and also when a theme that had no palette file of
        // its own grows one, which is why a nil watcher is retried rather than remembered as
        // absent.
        let wanted = config.theme.name.isEmpty ? nil : config.theme.name
        if wanted != watchedPalette {
            paletteWatcher?.stop()
            paletteWatcher = nil
            watchedPalette = wanted
        }
        guard let wanted else { return }
        // The palette *file*, with its directory watched alongside it — the same shape as the
        // watch on `toe.toml`, and for the same two reasons. A kqueue on a directory reports an
        // entry being added, removed or renamed, so an editor that saves in place by truncating
        // `colors.toml` would never be seen by a watch on the folder; and an editor that saves
        // atomically by renaming a temporary file over it kills a watch bound only to the
        // original descriptor, which is what the parent watch is for.
        paletteWatcher = watch(ThemeStore.directory.appendingPathComponent(wanted)
                                 .appendingPathComponent("colors.toml"),
                               isDirectory: false, existing: paletteWatcher)
    }

    /// A watch that is started when its target is there and dropped when it is not.
    private func watch(_ url: URL, isDirectory wantsDirectory: Bool = true,
                       existing: ConfigWatcher?) -> ConfigWatcher? {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue == wantsDirectory else {
            existing?.stop()
            return nil
        }
        if let existing { return existing }
        let watcher = ConfigWatcher(url: url, watchesParent: !wantsDirectory,
                                    events: [.write, .extend, .delete, .rename])
        watcher.onChange = { [weak self] in self?.loadConfig(force: true) }
        watcher.start()
        return watcher
    }

    /// What the Style level of the menu is looking at, read fresh every time it opens.
    ///
    /// This is also the only place toe ever reaches the network, and it does not wait for it: the
    /// level draws from the catalogue already on disk, the request runs behind it, and what it
    /// finds is there the next time you look. `refreshIfStale` does nothing unless the list is
    /// missing or a day old.
    /// - Parameter opening: true when the menu is being opened — the act that asks for a
    ///   catalogue and for a fresh look at the themes directory. False when this is being rebuilt
    ///   underneath an *open* menu, where it runs six times a second for as long as a download
    ///   lasts: neither the directory nor the catalogue can change under it in that time, and two
    ///   directory listings at that rate is work for nothing. The stored `themes` and
    ///   `backgrounds` are what the last real look found, and `download`'s completion sets
    ///   `themes` itself before asking for a reload, so a theme that has just landed is in them.
    private func styleMenu(opening: Bool = true) -> StyleMenu {
        let current = config.theme.name.isEmpty ? nil : config.theme.name
        if opening {
            available.refreshIfStale()
            themes = ThemeStore.installed()
            if let current { backgrounds = ThemeStore.backgrounds(named: current) }
        }
        let installed = Themes.ordered(themes)
        themes = installed
        // The catalogue whole, installed themes included: `Style › Theme` reads the first field
        // and `Install › Style › Theme` reads this one, dimming what it finds in both.
        return StyleMenu(themes: installed, available: available.themes,
                         fetching: available.isFetching,
                         current: current,
                         backgrounds: backgrounds, currentBackground: currentBackground,
                         downloading: downloading)
    }

    /// Takes a theme off the disk, and off your border if you were wearing it.
    ///
    /// The order matters: the config is rewritten *first*, so that the moment the folder goes
    /// there is nothing left pointing at it. Doing it the other way round leaves a window — short,
    /// but real, because writing the config reloads it — in which the palette in effect names a
    /// directory that is no longer there, and toe would report the theme it just removed as
    /// broken rather than as gone.
    private func removeTheme(_ slug: String) {
        // Through the slug, because a hand-written config may say `name = "Tokyo Night"` where
        // the folder is `tokyo-night`, and the theme about to be deleted would otherwise not be
        // recognised as the one in effect.
        if slug == Slug.make(config.theme.name) { setTheme("") }
        guard ThemeStore.remove(named: slug) else { return }
        themes = ThemeStore.installed()
        refreshMenu()
    }

    /// Writes the theme into your config rather than holding it in memory, so it survives a
    /// restart and turns up in the file you version — and so that picking one here and editing
    /// the line by hand are the same act, producing the same reload.
    private func setTheme(_ slug: String) {
        // A theme you have not got is fetched first and set when it arrives, so choosing one from
        // the list does the same thing whether or not it happens to be on this machine already.
        // That is the only way one list of themes makes sense rather than two.
        if !slug.isEmpty, !themes.contains(where: { $0.slug == slug }),
           let remote = available.themes.first(where: { $0.slug == slug }) {
            return download(remote)
        }
        guard slug.isEmpty || themes.contains(where: { $0.slug == slug }) else {
            // Refused rather than written: putting a name that resolves to nothing into somebody
            // else's file, on their behalf, is worse than a log line they can go and read.
            Log.error("theme: there is no theme called '\(slug)'")
            return
        }
        rewriteConfig("theme", edit: { ThemeWriter.settingTheme(slug, in: $0) },
                      verify: { Slug.make($0.theme.name) == slug })
    }

    /// Flips one of the menu's Setup switches in the config file and answers the value now in
    /// effect. Which line to write is the switch's own business — see `ConfigSwitch`.
    ///
    /// Through the file rather than flipped in memory, because the file is where the setting
    /// lives: a flip the next reload put back would be a switch that throws itself. It also means
    /// the reload does the work — `border.apply` for the border, `applyMiscSettings` for the
    /// Dock — so the switch and the config file that says the same thing take the same path, and
    /// there is nothing here that only happens when a menu row was the one to ask.
    ///
    /// For the slide that path matters twice over: the first `on` arrives by
    /// `applyAnimationSetting` and asks for Screen Recording with the menu open on the row that
    /// asked — the one moment the prompt has a context, and better than a config save nobody was
    /// watching.
    private func toggle(_ setting: ConfigSwitch) -> Bool {
        let wanted = !setting.value(in: config)
        rewriteConfig(setting.key, edit: {
            ConfigWriter.setting(setting.key, to: wanted ? "true" : "false",
                                 inTable: setting.table, of: $0)
        }, verify: { setting.value(in: $0) == wanted })
        let now = setting.value(in: config)
        // The Dock is the one switch the reload above does not always act on: `autohide_dock` is
        // toe making sure the strip is there, and it leaves a Dock you hide yourself alone, so on
        // that machine the row would sit there saying `off` beside a Dock that never moved. The
        // switch says what it does instead — see `DockAutoHide.command`. Only when the file
        // actually changed: a write that was declined leaves the row, the file and the Dock
        // agreeing on the old value rather than the Dock alone on the new one.
        if setting == .dock, now == wanted { DockAutoHide.command(now) }
        return now
    }

    /// Edits `toe.toml` in place and reloads. `what` names the caller in the log.
    ///
    /// The writer works a line at a time and cannot see everything a parser can — `["theme"]`
    /// is the same table as `[theme]`, and a header inside a string is not a header at all. So
    /// its own output is parsed back before it is committed and `verify` is asked whether it says
    /// what it was asked to say, which turns every case the writer gets wrong from a config that
    /// will not load into a config that was left alone.
    private func rewriteConfig(_ what: String, edit: (String) -> String, verify: (Config) -> Bool) {
        guard let text = try? String(contentsOf: Coordinator.configURL, encoding: .utf8) else {
            Log.error("\(what): \(Coordinator.configURL.lastPathComponent) could not be read")
            return
        }
        let proposed = edit(text)
        guard proposed != text else { return }
        guard let check = try? Config.parse(proposed), verify(check) else {
            Log.error("\(what): declined to edit \(Coordinator.configURL.lastPathComponent) — "
                      + "the result would not have said what it was asked to say")
            return
        }
        guard ConfigFile.write(proposed, to: Coordinator.configURL) else { return }
        // Immediately, so the screen changes now; the watcher's echo 150 ms later sees the same
        // bytes and early-outs.
        loadConfig(force: true)
    }

    /// Fetches a theme, then sets it.
    ///
    /// The menu is still up — `Command.keepsMenuOpen` is true for every theme row — and the
    /// theme's own row fills as the pictures arrive. That is the only thing toe says about a
    /// download now: nine megabytes over a slow connection is long enough that silence would
    /// read as nothing having happened, and the row is where the spending was described in the
    /// first place, so it is where the eye already is.
    ///
    /// Dismissing the menu does not cancel anything — the fetch is on a utility queue and knows
    /// nothing about the panel. What it costs is the progress: close the menu and the download
    /// finishes unwatched, announcing itself by the screen changing colour. That is the accepted
    /// price of taking the strip out of the menu bar.
    private func download(_ theme: RemoteTheme) {
        guard downloading == nil else {
            Log.error("themes: already fetching something")
            return
        }
        downloading = ThemeDownload(slug: theme.slug, fetching: 0,
                                    total: theme.backgrounds.count,
                                    bytesDone: 0, bytesTotal: theme.bytes)
        refreshMenu()

        ThemeDownloader.fetch(theme, into: ThemeStore.directory,
                              progress: { [weak self] step in
                                  self?.downloading = step
                                  self?.refreshMenu()
                              },
                              completion: { [weak self] result in
            guard let self else { return }
            self.downloading = nil
            switch result {
            case .success:
                Log.info("themes: fetched \(theme.slug)")
                // This theme's own earlier failure, if any, is over; anyone else's stands.
                self.runtimeWarnings.removeValue(forKey: theme.slug)
                // Into `setTheme` rather than straight into the config: the download is a step on
                // the way to the same act, so it ends up in the same place, with the same write
                // and the same reload.
                self.themes = ThemeStore.installed()
                self.setTheme(theme.slug)
                // And then unconditionally, rather than trusting the reload inside `setTheme` to
                // have happened. It has five early returns — no such theme, the config
                // unreadable, the line already naming this theme, the rewritten file failing its
                // own parse, the write refused — and on every one of them there is no reload and
                // so no refresh. `downloading` is nil by here, so a menu that went unrefreshed
                // would keep drawing the last progress it was handed: a row stopped part-filled,
                // which is the one thing a finished download must not look like.
                //
                // The third of those returns is not hypothetical. Delete a theme's folder while
                // your config still names it, then fetch it again from the menu — a normal thing
                // to do to replace a theme — and the line needs no change, so nothing reloads.
                self.refreshMenu()
                // And the tooltip, for the same reason: the failure it may have carried for
                // this theme has just been taken down, and those early returns refresh nothing.
                self.refreshStatus()
            case .failure(let why):
                self.runtimeWarnings[theme.slug] = "\(theme.name) could not be fetched: \(why)"
                Log.error("themes: \(theme.slug): \(why)")
                // The tooltip still carries a failure — that is a thing that went wrong rather
                // than progress, and the row it happened on has gone back to saying its size.
                self.refreshStatus()
                self.refreshMenu()
            }
        })
    }

    private func setBackground(_ file: String) {
        // Only ever a name out of the enumerated list, so a string from a config file cannot be
        // joined onto a directory as a path of its own.
        guard backgrounds.contains(file), !config.theme.name.isEmpty else {
            Log.error("background: '\(file)' is not one of the current theme's")
            return
        }
        wallpaper.set(ThemeStore.background(named: file, in: config.theme.name))
        currentBackground = file
        BackgroundStore.save(file)
    }

    /// Starts and stops the dock swipe tap as the config flips, on every reload as well as at
    /// startup. A no-op until Accessibility has landed; `beginManaging()` calls it again then.
    /// This is also the whole of the gate on the swipe *switching workspaces*: with the setting
    /// off the tap does not exist, so `onSwipe` cannot fire, and a second check anywhere else
    /// would be a redundancy waiting to drift.
    private func applyDockSwipeSetting() {
        guard isManaging else { return }
        // `setupWarnings`, never `runtimeWarnings`: this is the one place the reload-rebuilt list
        // is started over, and a download failure has no business being on it.
        setupWarnings.removeAll()

        guard config.gestures.swallowDockSwipes else {
            dockSwipes.stop()
            return
        }
        if !dockSwipes.isRunning, !dockSwipes.start() {
            setupWarnings = ["dock swipe tap could not be created — swipes are not swallowed"]
        }
    }

    /// The slide's permission and its picture of the displays, when `animations.slide_on_swipe`
    /// asks for them. After `applyDockSwipeSetting`, which starts `setupWarnings` afresh, and
    /// gated on `isManaging` like it: a swipe cannot arrive before the tap exists, so neither
    /// can the need for a picture. With the setting off nothing here runs — no prompt, no
    /// ScreenCaptureKit, no reminder from macOS 15 that toe can record the screen.
    private func applyAnimationSetting() {
        guard isManaging, config.animations.slideOnSwipe else { return }
        guard ScreenSnapshot.isGranted else {
            setupWarnings.append("the slide needs Screen Recording — grant it in System Settings "
                                 + "› Privacy & Security, then relaunch toe")
            snapshot.requestOnce()
            return
        }
        snapshot.refresh()
    }

    /// The macOS behaviours toe takes over, applied at startup and on every reload. None of them
    /// needs Accessibility, but all are gated on `isManaging` so they arrive together with the
    /// tap rather than flickering on before toe can actually manage anything.
    private func applyMiscSettings() {
        guard isManaging else { return }

        if config.misc.disableExposeShortcuts {
            SymbolicHotkeys.disable(SymbolicHotkeys.expose)
        } else {
            SymbolicHotkeys.restoreAll()
        }

        if config.misc.disableWallpaperClick {
            WallpaperClick.disable()
        } else {
            WallpaperClick.restore()
        }

        if config.misc.disableEdgeTiling {
            EdgeTiling.disable()
        } else {
            EdgeTiling.restore()
        }

        if config.misc.autohideDock {
            DockAutoHide.enable()
        } else {
            DockAutoHide.restore()
        }

        if config.misc.preventHiding {
            hideBlocker.start()
        } else {
            hideBlocker.stop()
        }
    }

    /// Puts the layout and the focus back after an application toe unhid has returned.
    ///
    /// A hidden window keeps the frame it had, so `desired` still matches it and `apply` would
    /// write nothing — which is what leaves the windows looking wrong once they are back. Dropping
    /// this application's bookkeeping forces its tiles to be written again, and the correction
    /// budget goes with it, because coming back from a hide is not an app fighting for its own
    /// geometry.
    private func relayoutAfterUnhide(_ pid: pid_t) {
        for (id, window) in tracker.windows where window.pid == pid {
            desired.removeValue(forKey: id)
            corrections.removeValue(forKey: id)
        }
        apply(refocus: false)

        // `activate()` gave the application back the foreground; this gives the focus back to the
        // window that had it. Deliberately not `focusApplied`: hiding an application makes macOS
        // activate whichever one is behind it, and that activation reaches toe as an ordinary
        // focus change — often before the hide notification does — so by now `focusApplied` names
        // a window belonging to some other app. `focusHistory` is most-recent-first and survives
        // that, so asking it for this application's own last-focused window is race-free.
        if let id = workspaces.focusHistory.first(where: { tracker.window($0)?.pid == pid }) {
            focus(id)
        }
    }

    private func refreshStatus() {
        // No progress line any more. Both things that used to put one here — a theme downloading
        // and the catalogue being fetched — are said in the quick menu now, the first by the
        // theme's own row filling and the second by the note row that was always there. The strip
        // is back to workspaces and the tooltip to things that have gone wrong, which is what the
        // menu bar is for: `⟳ Gruvbox 3/6` was a second, worse copy of a list the menu draws
        // properly, and it was on screen at the moment the user was looking at the menu anyway.
        // Sorted so the tooltip does not reorder itself between two refreshes; the dictionary
        // has no order of its own.
        status.update(workspaces: workspaceStates(),
                      warnings: warnings + setupWarnings + runtimeWarnings.values.sorted(),
                      accessibilityGranted: AXIsProcessTrusted())
    }

    /// Pushes the theme state into the menu, if it is open.
    ///
    /// Separate from `refreshStatus` and deliberately not called from it: `refreshStatus` runs on
    /// every focus change, and this rebuilds the menu's whole tree and re-lays the panel out.
    /// Called only where what the menu draws has actually changed — a download starting,
    /// stepping on, finishing or failing; the catalogue arriving; and a reload, which is what
    /// carries a newly applied theme's colours into the panel as well as its `current` marker.
    private func refreshMenu() {
        guard quickMenu.isVisible else { return }
        quickMenu.update(config: config, style: styleMenu(opening: false))
    }

    /// What the strip in the menu bar title draws. This runs on every focus change and every
    /// adopted window, so it stays to what the strip actually reads — no window lists, no app
    /// names, and above all no icons.
    private func workspaceStates() -> [WorkspaceStrip.State] {
        let focusedIndex = workspaces.focusedWorkspaceIndex

        return (1...WorkspaceManager.workspaceCount).map { index in
            WorkspaceStrip.State(index: index,
                                 isFocused: index == focusedIndex,
                                 isVisible: workspaces.monitorShowing(workspace: index) != nil,
                                 isEmpty: workspaces.isEmpty(workspace: index))
        }
    }

    // MARK: - Monitors

    private func refreshMonitors() {
        let monitors = NSScreen.screens.map { screen in
            Monitor(id: screen.displayID,
                    frame: Coordinates.toAX(screen.frame),
                    usable: Coordinates.toAX(screen.visibleFrame))
        }
        guard !monitors.isEmpty else { return }
        workspaces.setMonitors(monitors)
    }

    /// Where a hidden workspace's windows are parked. See `Stash.origin` — this needs no
    /// private API, and the trade-off is that stashed windows stay visible to Cmd-Tab.
    private func stashPoint(for window: ManagedWindow) -> CGPoint {
        let index = workspaces.workspaceIndex(of: window.id)
        let monitorID = index.flatMap { workspaces.workspaces[$0]?.monitorID } ?? workspaces.focusedMonitorID
        guard let monitor = workspaces.monitor(id: monitorID) else { return .zero }
        let size = window.element.size ?? CGSize(width: monitor.usable.w, height: monitor.usable.h)
        let origin = Stash.origin(windowSize: Point(x: size.width, y: size.height),
                                  on: monitor, monitors: workspaces.monitors)
        return CGPoint(x: origin.x, y: origin.y)
    }

    /// Parks a window off-screen, where its hidden workspace keeps its windows.
    private func park(_ window: ManagedWindow) {
        window.frameBeforeStash = window.element.frame
        window.isStashed = true
        desired.removeValue(forKey: window.id)
        corrections.removeValue(forKey: window.id)
        WindowMover.setPosition(stashPoint(for: window), element: window.element, pid: window.pid)
    }

    /// Settles the stashes `apply` could not make, once the windows owing them have left native
    /// fullscreen.
    ///
    /// The sequence this exists for: fullscreen a tiled window, switch workspace while it is
    /// fullscreen, then leave fullscreen. macOS closes the fullscreen Space and restores the
    /// window to the frame it had before — its old tile, on a workspace that is no longer
    /// showing — so it lands on top of the workspace that is, managed by nothing.
    ///
    /// The window is not pushed away: its workspace is brought to it. Leaving fullscreen is the
    /// user saying they want this window back at its ordinary size, and hiding it a frame later
    /// answers a question nobody asked — where a workspace switch says plainly which window they
    /// are looking at, and puts it in its tile with the rest of its workspace around it. This is
    /// `moveToWorkspace`'s `follow`, arrived at from the other end.
    ///
    /// A second window owing a stash cannot also be followed, so it is parked as `apply` would
    /// have parked it. Two windows leaving fullscreen in the same breath is not a real sequence;
    /// leaving one of them on top of a workspace it does not belong to is the bug above.
    private func settleFullscreenReturns(preferring preferred: WindowID? = nil) {
        guard tracker.windows.values.contains(where: { $0.stashPending }) else { return }

        // Sorted, because `tracker.windows` is a dictionary and which window gets followed must
        // not depend on its hashing. The window the caller heard from wins outright.
        var returned = tracker.windows.values
            .filter { $0.stashPending && !$0.element.isFullscreen }
            .sorted { $0.id < $1.id }
        if let preferred, let at = returned.firstIndex(where: { $0.id == preferred }) {
            returned.insert(returned.remove(at: at), at: 0)
        }
        guard let follow = returned.first else { return }
        for window in returned { window.stashPending = false }
        for window in returned.dropFirst() { park(window) }

        guard let index = workspaces.workspaceIndex(of: follow.id) else {
            park(follow)
            return
        }
        workspaces.switchTo(workspace: index)
        // After the switch, which refocuses the workspace's own last window: the one that just
        // came back from fullscreen is the window the user is actually looking at.
        workspaces.noteFocus(follow.id)
        // `apply` clears `isStashed` and writes the tile. The window may still be animating out
        // of fullscreen and clobber that frame on the way — which is the ordinary case
        // `corrections` handles, on the move notification that follows.
        apply(refocus: true)
    }

    // MARK: - Switching workspaces

    /// The model half of `workspace <target>`, without the render. `dispatch` wants both and
    /// takes them in a row; the swipe wants a picture of the screen between the two, which is
    /// the only reason this is not inline there.
    private func switchWorkspace(_ target: WorkspaceTarget) {
        switch target {
        case .index(let n): workspaces.switchTo(workspace: n)
        case .next: workspaces.switchToRelativeWorkspace(1)
        case .previous: workspaces.switchToRelativeWorkspace(-1)
        case .former: workspaces.switchToPreviousWorkspace()
        }
    }

    /// `workspace <target>` from the trackpad: the switch `dispatch` makes, with the slide
    /// `animations.slide_on_swipe` asks for laid over it when it can be.
    ///
    /// Whether the display's content actually changes is read off `activeWorkspace` for the
    /// display that had the focus *before* the switch: `.next` can land on a workspace that
    /// lives on the other display, in which case `switchTo` moves the focus there and nothing on
    /// this one moves — no slide. `render()` would be the wrong test: it recalculates layouts
    /// as a side effect, and two workspaces whose windows happen to tile alike would read as
    /// unchanged when the screen has in fact changed.
    private func swipeToWorkspace(_ target: WorkspaceTarget) {
        // Whatever slide is in flight, the screen under it is already the end of that switch.
        cancelSlide()

        let monitorID = workspaces.focusedMonitorID
        let before = workspaces.activeWorkspace[monitorID]
        // Where the windows are *now*, and which of them wears the border, for the mask on the
        // outgoing picture. After the switch the model has forgotten both. Only with the slide
        // on: this is a render and a corner-radius query per window, on every swipe.
        let leaving = config.animations.slideOnSwipe
            ? workspaces.monitor(id: monitorID).map {
                slideCutouts(workspaces.render(), on: $0, border: workspaces.focusedWindow)
            } ?? []
            : []
        switchWorkspace(target)
        let after = workspaces.activeWorkspace[monitorID]

        guard config.animations.slideOnSwipe, before != after,
              let direction = WorkspaceSlide.direction(for: target),
              let monitor = workspaces.monitor(id: monitorID)
        else { apply(refocus: true); return }

        // The grant may have landed since the config was applied — read it now, and if the
        // displays have not been listed since, list them for the next swipe. This one switches
        // the plain way rather than wait on an enumeration of every window on the system.
        guard ScreenSnapshot.isGranted else { apply(refocus: true); return }
        guard snapshot.knows(display: monitor.id) else {
            snapshot.refresh()
            apply(refocus: true)
            return
        }

        // A native-fullscreen window on this display means the swipe is switching workspaces
        // behind a Space the user cannot see them on; a panel over it would be the one thing
        // they did see. The border's rule, and its helper: scoped to a display, never "is
        // anything fullscreen".
        guard !BorderGeometry.isBehindFullscreen(window: monitor.usable,
                                                  fullscreen: AX.frontmostFullscreenFrame)
        else { apply(refocus: true); return }

        beginSlide(direction, on: monitor, leaving: leaving)
    }

    /// The windows on `monitor` in `plan`, as the mask for a picture of it — each at the radius
    /// the window server rounds it to, and the focused one grown by the border so the ring
    /// slides with its window instead of being cut off at the window's edge.
    private func slideCutouts(_ plan: RenderPlan, on monitor: Monitor,
                              border focused: WindowID?) -> [WorkspaceSlide.Cutout] {
        var windows: [(box: Box, radius: Double)] = []
        for (id, box) in plan.frames.merging(plan.floating, uniquingKeysWith: { _, floating in floating }) {
            let radius = Double(WindowCornerRadius.points(for: id) ?? SystemCornerRadius.points)
            if id == focused, config.border.enabled, config.border.width > 0 {
                let w = config.border.width
                windows.append((BorderGeometry.outset(box, by: w),
                                BorderGeometry.outerRadius(inner: radius, width: w)))
            } else {
                windows.append((box, radius))
            }
        }
        return WorkspaceSlide.cutouts(windows, in: monitor.usable)
    }

    /// The sequence: picture of the screen as it is → panel up showing it → the real switch,
    /// hidden under the panel → a beat for the apps to paint → picture of the result → both
    /// pictures slide → panel down. Every step checks it still belongs to the current slide,
    /// because every step is asynchronous and a second swipe, a render from elsewhere or a
    /// display change can have moved on without it. The model is already switched when this is
    /// called; what is owed is the `apply`, and every path out of here makes it exactly once.
    private func beginSlide(_ direction: WorkspaceSlide.Direction, on monitor: Monitor,
                            leaving outgoingCutouts: [WorkspaceSlide.Cutout]) {
        slideGeneration += 1
        let mine = slideGeneration
        let started = Date()
        func ms() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

        slidePhase = .awaitingPicture

        // The switch is not held for a picture that is not coming. A late one finds the phase
        // moved on and is dropped.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.slidePictureDeadline) { [weak self] in
            guard let self, self.slideIs(.awaitingPicture, mine) else { return }
            Log.info("slide: no picture after \(ms()) ms, switching without one")
            self.slidePhase = .idle
            self.apply(refocus: true)
        }

        // Two pictures at once — the screen, and the wallpaper under it — and the panel goes up
        // when the second lands. The wallpaper is allowed to fail: without it the whole picture
        // slides, wallpaper and all, which is how the first version looked.
        var screen: CGImage??
        var wallpaper: CGImage??
        let proceed = { [weak self] in
            guard let self, self.slideIs(.awaitingPicture, mine),
                  let screen, let wallpaper else { return }
            guard let image = screen else {
                self.slidePhase = .idle
                self.apply(refocus: true)
                return
            }
            Log.info("slide: outgoing picture after \(ms()) ms"
                     + (wallpaper == nil ? " — no wallpaper picture, sliding the whole screen" : ""))
            self.slidePhase = .switching
            self.slide.begin(showing: image, over: monitor.usable, wallpaper: wallpaper,
                             cutouts: outgoingCutouts)

            // The switch itself, once the panel is on screen. Still `.switching` if it runs: a
            // cancel in the meantime came from a caller that renders next itself.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.slidePanelLatency) { [weak self] in
                guard let self, self.slideIs(.switching, mine) else { return }
                self.apply(refocus: true)
                Log.info("slide: switched after \(ms()) ms")

                DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideSettleTime) { [weak self] in
                    guard let self, self.slideIs(.switching, mine) else { return }
                    self.snapshot.capture(display: monitor.id, area: monitor.usable, frame: monitor.frame,
                                          of: .everythingButToe) { [weak self] image in
                        guard let self, self.slideIs(.switching, mine) else { return }
                        Log.info("slide: incoming picture after \(ms()) ms"
                                 + (image == nil ? " — none, revealing instead" : ""))
                        // The border is not in this picture — toe is excluded from it — so no
                        // window is grown for it.
                        let cutouts = self.slideCutouts(self.workspaces.render(), on: monitor, border: nil)
                        self.slidePhase = .sliding
                        self.slide.push(image, cutouts: cutouts, direction: direction,
                                        duration: self.config.animations.slideDuration) { [weak self] in
                            guard let self, self.slideIs(.sliding, mine) else { return }
                            self.slidePhase = .idle
                            Log.info("slide: done after \(ms()) ms")
                        }
                    }
                }
            }
        }
        snapshot.capture(display: monitor.id, area: monitor.usable, frame: monitor.frame,
                         of: .everything) { image in
            screen = .some(image)
            proceed()
        }
        snapshot.capture(display: monitor.id, area: monitor.usable, frame: monitor.frame,
                         of: .wallpaper) { image in
            wallpaper = .some(image)
            proceed()
        }
    }

    /// Whether a callback started for slide `generation` still has that slide, at `phase`, to
    /// act on. Every asynchronous step of `beginSlide` asks this first.
    private func slideIs(_ phase: SlidePhase, _ generation: Int) -> Bool {
        slideGeneration == generation && slidePhase == phase
    }

    /// Takes the slide down, whatever step it is at. Never renders: a slide still waiting for
    /// its picture has a switch owed, and every caller of this either renders next or starts
    /// another slide that will.
    private func cancelSlide() {
        guard slidePhase != .idle else { return }
        slideGeneration += 1
        slidePhase = .idle
        slide.cancel()
    }

    // MARK: - WindowTrackerDelegate

    func windowAppeared(_ window: ManagedWindow, shouldFloat: Bool) {
        // A window a restored session already placed is left exactly as the snapshot has it:
        // its workspace, its slot in the tree, and the floating frame it was remembered with,
        // which is better than the frame it happens to be wearing now — that one is the tile
        // toe gave it before the restart.
        if workspaces.workspaceIndex(of: window.id) == nil {
            // Adopt time is the only moment a window's own geometry is known — the first tile
            // write clobbers it. This is Hyprland's `m_vLastFloatingSize` / `..Position`, and it
            // is what a window returns to the first time you float it.
            workspaces.floatingFrames[window.id] = window.element.frame
            workspaces.addWindow(window.id, floating: shouldFloat)
        }
        apply(refocus: false)
        refreshStatus()
    }

    func windowDisappeared(_ id: WindowID) {
        workspaces.removeWindow(id)
        workspaces.floatingFrames.removeValue(forKey: id)
        desired.removeValue(forKey: id)
        corrections.removeValue(forKey: id)
        settleWork.removeValue(forKey: id)?.cancel()
        settleAttempts.removeValue(forKey: id)
        if focusApplied == id { focusApplied = nil }
        apply(refocus: false)
    }

    func windowFocused(_ id: WindowID) {
        guard workspaces.workspaceIndex(of: id) != nil, !isEchoOfOwnRaise(id) else { return }
        workspaces.noteFocus(id)
        focusApplied = id
        // Clicking a window raises it, so the focused one is already in front and stays there;
        // this is only about the float it has just taken the focus from.
        sinkUnfocusedFloats(workspaces.render())
        updateBorder()
        refreshStatus()
        scheduleSessionSave()
    }

    /// Chromium, Electron and the JetBrains IDEs restore their own remembered geometry a beat
    /// after the window is created, clobbering the frame toe just wrote. Re-asserting on the
    /// move/resize notification is what actually makes those apps tile — and it doubles as
    /// snap-back when a window is dragged out of its tile.
    func windowFrameChangedExternally(_ id: WindowID, resized: Bool) {
        guard let window = tracker.window(id) else { return }
        guard !window.isStashed else {
            // Coming out of fullscreen is a move and a resize, and it arrives after the Space
            // change rather than with it — by which point the window has finished animating back
            // to a frame worth remembering. `activeSpaceChanged` usually gets there first; this
            // is the one that is right about the frame.
            if window.stashPending { settleFullscreenReturns(preferring: id) }
            return
        }
        // A move the user is making by hand hides the border until they let go; see DragMonitor.
        // `desired[id]` is the tile they took hold of, and a float — which has none — passes nil,
        // so a resize of one is never measured against anything.
        if id == workspaces.focusedWindow {
            drag.noteExternalFrameChange(id, resized: resized, tile: desired[id])
        }

        if workspaces.isFloating(id) {
            workspaces.floatingFrames[id] = window.element.frame
            scheduleSettle(id)
            if id == workspaces.focusedWindow { updateBorder() }
            return
        }

        // A tile is re-asserted against an app that fights it, never against the user. Where the
        // window has got to during the drag says nothing about where it belongs — the pointer
        // decides that, in `swapWithWindow` — so leave it alone until they let go. The border
        // still gets a look in: this is where it drops behind the window at the start of a drag,
        // and where it re-takes that place if the app raises itself mid-drag.
        if id == draggedWindow {
            updateBorder()
            return
        }

        guard let want = desired[id], let have = window.element.frame else { return }
        if Self.settled(have, want) {
            corrections[id] = 0
            settleAttempts.removeValue(forKey: id)
            if id == workspaces.focusedWindow { updateBorder() }
            return
        }

        // The correction below is immediate because the app it is aimed at is: Chromium writes
        // its remembered geometry once, and answering it a notification later would show the
        // wrong frame for as long as it took. macOS's edge-snap is the opposite — it animates,
        // and the three attempts go on frames that had not finished moving, after which toe has
        // given up and the window stays flush with the display edge while the tree is still laid
        // out around the tile it left. So the tile is asserted once more when the window has
        // stopped moving, which is the one moment a write can hold.
        scheduleSettle(id)

        let attempts = corrections[id, default: 0]
        guard attempts < 3 else { return }   // the app will not comply; stop fighting it
        corrections[id] = attempts + 1
        WindowMover.setFrame(want, element: window.element, pid: window.pid)
        if id == workspaces.focusedWindow { updateBorder() }
    }

    /// Puts a window back where toe wants it once whatever moved it has finished: a float back
    /// inside `gaps_out`, a tile back in its tile.
    ///
    /// `endDrag` already settles the frame the user let go of, and for a drag that is the end of
    /// it. macOS's own edge-snap is what this is for: dragging a window to the side of the
    /// display tiles it to that half — and dragging it to the top fills the screen — *after* the
    /// mouse comes up, over the top of the frame the release settled, flush with the display
    /// edge where every tile around it keeps the margin clear. That frame arrives here like any
    /// other external move, so it is settled like any other. What that means differs by what the
    /// window is: a float keeps the half of the display the snap chose, inset to the margin,
    /// because a float is the user's to place — while a tile is not, so it goes back into the
    /// tile the tree still has it in, which is the only frame that leaves the layout whole.
    ///
    /// Debounced, because the snap animates and each frame of it arrives separately — settling
    /// the first would have toe writing one position while macOS writes the next, and would
    /// spend the attempt cap below on frames of an animation that had not finished moving.
    /// Debouncing also keeps it clear of a live drag: the guard below is what actually decides,
    /// but a user who pauses mid-drag would otherwise reach the deadline while still holding on.
    private func scheduleSettle(_ id: WindowID) {
        settleWork[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settle(id) }
        settleWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleLatency, execute: work)
    }

    private func settle(_ id: WindowID) {
        settleWork.removeValue(forKey: id)
        guard id != draggedWindow, let window = tracker.window(id), !window.isStashed
        else { return }
        if workspaces.isFloating(id) {
            settleFloat(id, window)
        } else {
            settleTile(id, window)
        }
    }

    private func settleFloat(_ id: WindowID, _ window: ManagedWindow) {
        // Read afresh: the deadline is long enough for the frame recorded on the notification
        // that scheduled this to be a frame of an animation that has since finished.
        if let have = window.element.frame { workspaces.floatingFrames[id] = have }
        guard workspaces.settleFloat(id) else {
            settleAttempts.removeValue(forKey: id)
            return
        }
        let attempts = settleAttempts[id, default: 0]
        guard attempts < 3 else { return }   // the app will not comply; stop fighting it
        settleAttempts[id] = attempts + 1
        // A window moving with nobody touching it is the kind of thing that wants an answer in
        // the log rather than a guess: this is the one place toe moves a float of its own accord.
        Log.info("brought floating window \(id) back inside gaps_out")
        apply(refocus: false)
    }

    /// The tile is written here rather than through `apply`, which would not do it: nothing about
    /// the plan has changed — the tree never heard about the snap — so `desired[id]` still holds
    /// the frame this window is supposed to have and `apply` skips every window it already
    /// matches. This is the same write `windowFrameChangedExternally` makes, taken once more now
    /// that the window has stopped moving.
    private func settleTile(_ id: WindowID, _ window: ManagedWindow) {
        // Read afresh: the deadline is long enough for the frame on the notification that
        // scheduled this to be a frame of an animation that has since finished.
        guard let want = desired[id], let have = window.element.frame, !Self.settled(have, want)
        else {
            settleAttempts.removeValue(forKey: id)
            return
        }
        // Three, as everywhere else, and a snap spends two of them: macOS pushes the window
        // back to the half it chose once, about a fifth of a second after the first write, and
        // lets go of it after the second. The third is what is left for an app that will not
        // comply — one whose minimum size exceeds its tile — which is where this stops.
        let attempts = settleAttempts[id, default: 0]
        guard attempts < 3 else { return }
        settleAttempts[id] = attempts + 1
        // Same reasoning as the float above: a window that moved with nobody touching it wants
        // an answer in the log.
        Log.info("put tiled window \(id) back in its tile")
        WindowMover.setFrame(want, element: window.element, pid: window.pid)
        if id == workspaces.focusedWindow { updateBorder() }
    }

    /// Apps round and clamp the frames they are given; two frames within 2pt of each other are
    /// the same frame as far as toe is concerned.
    private static func settled(_ a: Box, _ b: Box) -> Bool {
        abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2 && abs(a.w - b.w) < 2 && abs(a.h - b.h) < 2
    }

    func screensChanged() {
        // A slide in flight is a picture of a screen that no longer exists in that shape.
        cancelSlide()
        refreshMonitors()
        snapshot.refresh()
        desired.removeAll()
        corrections.removeAll()
        apply(refocus: false)
        // After the layout, never before: a display appearing is a moment the windows have to be
        // put somewhere, and the desktop picture is cosmetic. `reapply` is a no-op unless a
        // screen is actually showing something else.
        wallpaper.reapply()
    }

    /// Nothing about the layout has changed — only what is stacked over the focused window,
    /// which is what decides whether the border can sit above everything.
    func windowStackChanged() {
        // Somebody else has re-ordered the stack — most often an application coming forward,
        // which brings all of its windows with it, float included. That is the one thing toe
        // cannot predict from its own state, so the floats are put back down from what the
        // window server says is up there now, before the border is asked where it belongs.
        sinkUnfocusedFloats(workspaces.render())
        updateBorder()
    }

    /// A different Space is on show. The layout is untouched and so is the stacking inside it,
    /// so the floats are left exactly where they are — the border is the only thing that cares,
    /// because the window now in front may be a fullscreen one it must not draw over.
    func activeSpaceChanged() {
        // Before the border, because it may be about to change which workspace is showing:
        // leaving a fullscreen Space is a Space change, and it is the moment a window that went
        // fullscreen on a since-hidden workspace asks for its workspace back.
        settleFullscreenReturns()
        updateBorder()
        // With *Displays have separate Spaces* on — the macOS default — a desktop picture is set
        // per Space and not per screen, so a Space that has not been visited since the theme
        // changed is still showing the old one. `reapply` checks before it writes, which is what
        // makes this affordable on a callback that fires every time you change Space.
        wallpaper.reapply()
    }

    // MARK: - Applying the layout

    private func apply(refocus: Bool) {
        // A slide waiting for its picture has switched the model and not yet the screen. A render
        // arriving now from anywhere else — a window appearing, a config reload — puts the new
        // layout on screen before the picture of the old one is taken, and the picture would then
        // be of the wrong workspace: so the slide is dropped and this render is the switch, made
        // the instant way. A render during the slide itself means the screen has changed under
        // the pictures, and the honest thing is to show it. In between, while the pictures are
        // being made, a render is part of the end state the second picture will show — the
        // swipe's own switch above all — and is left alone.
        switch slidePhase {
        case .awaitingPicture, .sliding: cancelSlide()
        case .idle, .switching: break
        }

        let plan = workspaces.render()

        for id in plan.stashed {
            guard let window = tracker.window(id), !window.isStashed else { continue }
            // A native-fullscreen window is on a Space of its own and will not take a position,
            // so parking it fails silently — and the window then walks back onto whichever
            // workspace is showing the moment the user leaves fullscreen, tiled by nobody. The
            // stash is owed instead, and `settleFullscreenReturns` calls it in — by bringing the
            // workspace back to the window. No frame is remembered: the one it is wearing now is
            // the display, not the tile it came from.
            //
            // The AX round trip costs nothing on the common path — the guard above has already
            // dropped every window that is parked, so this only asks about the handful a
            // workspace switch is actually moving.
            if window.element.isFullscreen {
                window.frameBeforeStash = nil
                window.isStashed = true
                window.stashPending = true
                desired.removeValue(forKey: id)
                corrections.removeValue(forKey: id)
                continue
            }
            park(window)
        }

        // Floating frames deliberately bypass `desired` / `corrections`: that machinery exists
        // to re-assert a tile against an app that fights it, and pointing it at a floating
        // window would fight the user's own drags instead. Writing only on a real difference
        // makes this a no-op on every render but the one that changed something — floating a
        // window, bringing its workspace back, or losing the display it was remembered on.
        for (id, box) in plan.floating {
            guard let window = tracker.window(id) else { continue }
            window.isStashed = false
            if let have = window.element.frame, Self.settled(have, box) { continue }
            WindowMover.setFrame(box, element: window.element, pid: window.pid)
        }

        for (id, box) in plan.frames {
            guard let window = tracker.window(id) else { continue }
            window.isStashed = false
            guard desired[id] != box else { continue }
            desired[id] = box
            corrections[id] = 0
            // Writing this one would yank it out from under the cursor mid-drag; `endDrag`
            // puts it in its tile once the drag is over. Its swap partner moves normally,
            // and that is the feedback the user sees.
            if id == draggedWindow { continue }
            WindowMover.setFrame(box, element: window.element, pid: window.pid)
        }

        sinkUnfocusedFloats(plan)

        if refocus, let target = plan.focus, target != focusApplied,
           let window = tracker.window(target) {
            focusApplied = target
            WindowMover.focus(window)
        }

        updateBorder()
        refreshStatus()
        scheduleSessionSave()
    }

    private func updateBorder() {
        guard config.border.enabled,
              let focused = draggedWindow ?? workspaces.focusedWindow,
              let window = tracker.window(focused),
              !window.isStashed
        else {
            border.hide()
            return
        }

        // An edge in the user's hand gets no border at all, and the decision is made here,
        // before the round trip below, because `windowFrameChangedExternally` comes through on
        // every notification of a live resize. The tile is the one thing the user is changing,
        // so a ring around it would mark exactly the wrong rectangle, and the window trails its
        // notifications by too much to follow — the same reasoning that leaves a floating drag
        // without one. The `apply` in `endDrag` brings it back.
        if focused == draggedWindow, drag.kind == .resize {
            border.hide()
            return
        }

        // Read once, after the cheap conditions rather than among them: it costs a
        // cross-process Accessibility round trip, and the guard above already turns the border
        // off in every case where there was nothing to draw. Both `show` paths below test
        // against it, because either can be the one pointed at a fullscreen display.
        let fullscreen = AX.frontmostFullscreenFrame

        // While the user has hold of a window the border marks the tile it will land in rather
        // than the window itself. Two reasons, and they point the same way: toe hears about the
        // window's own movement through Accessibility, well behind the fact, so a border chasing
        // it would trail across the screen — and the tile is the useful thing to show anyway,
        // because the swap has already happened and that is where letting go puts it. A floating
        // window has no tile, so it keeps the old behaviour of no border until it is dropped.
        if focused == draggedWindow {
            // Behind the window being dragged, and above every other one — where Hyprland puts
            // it, since it draws each border with its own window and the focused window last.
            if let tile = desired[focused],
               !BorderGeometry.isBehindFullscreen(window: tile, fullscreen: fullscreen) {
                border.show(around: tile, of: focused, depth: .behindFrontmost)
            } else {
                border.hide()
            }
            return
        }

        // Prefer the frame we wrote; fall back to asking the window for floating ones.
        if let box = window.element.frame ?? desired[focused],
           !BorderGeometry.isBehindFullscreen(window: box, fullscreen: fullscreen) {
            border.show(around: box, of: focused, depth: borderDepth(around: box, of: focused))
        } else {
            border.hide()
        }
    }

    /// Where the border belongs in the stack.
    ///
    /// Above every ordinary window is right almost always — but a `.floating` panel is
    /// composited above every ordinary window whatever the real z-order says, so a dialog
    /// opened over the focused window had the ring drawn straight through it. When something
    /// really is stacked over the band, the ordinary level puts the border back underneath the
    /// active application, where it belongs: still above every inactive app, so the ring stays
    /// visible all the way round, with the window in front covering only what it overlaps.
    private func borderDepth(around box: Box, of id: WindowID) -> BorderOverlay.Depth {
        let above = WindowStack.ordinaryWindowsAbove(id)
        return BorderGeometry.bandIsCovered(window: box, width: config.border.width, by: above)
            ? .behindFrontmost : .aboveEverything
    }

    /// Sends every floating window that has lost the focus behind the tiles it covers.
    ///
    /// `togglefloating` raises a float, and focusing it raises it again — right while it is the
    /// window in hand, wrong the moment the focus moves on, because the float was then left
    /// sitting over half of whichever tile the focus had moved to. Accessibility has no lower
    /// action, so the way down is to raise what the float covers; see `Stacking.raiseOrder`,
    /// which works out the shortest set of raises that gets there.
    ///
    /// Not while a window is being dragged: the stack the user is looking at then is one they
    /// are making themselves, and the drag ends in an `apply` that settles it anyway.
    private func sinkUnfocusedFloats(_ plan: RenderPlan) {
        guard draggedWindow == nil else { return }
        // One focus change reaches this several ways over — the command, the notification the
        // application sends back, the render that follows — so the order is worked out against
        // the stack as it really is, and a float already at the bottom asks for no raises at
        // all. Without that, the repeats are what the user sees as flicker.
        let order = Stacking.raiseOrder(tiles: plan.frames,
                                        floats: plan.floating,
                                        focused: workspaces.focusedWindow,
                                        stackedAbove: WindowStack.windowsAbove)
        guard !order.isEmpty else { return }

        let now = ProcessInfo.processInfo.systemUptime
        selfRaised = selfRaised.filter { now - $0.value < Self.raiseEchoWindow }
        for id in order {
            guard let window = tracker.window(id), !window.isStashed else { continue }
            selfRaised[id] = now
            WindowMover.raise(window)
        }
    }

    /// Whether a focus notification is toe's own restacking coming back at it.
    ///
    /// Raising a window makes it its application's focused window, and the notification that
    /// arrives is the very one a click produces — nothing in it tells the two apart. Taken at
    /// face value it is a loop: toe hands the focus to a window it only meant to re-order, that
    /// focus sinks a float, sinking raises more windows, and every one of those reports a focus
    /// change of its own. The window toe is focusing for real is the exception — it is raised
    /// on purpose, and its echo is the truth.
    private func isEchoOfOwnRaise(_ id: WindowID) -> Bool {
        guard id != focusApplied, let raisedAt = selfRaised[id] else { return false }
        // Raising a window does not bring its application forward, so a window toe raised that
        // reports the focus from an application which is not the frontmost one is an echo
        // however long it took to arrive. A click is never that: it activates as it focuses.
        if let window = tracker.window(id),
           NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid {
            return true
        }
        guard ProcessInfo.processInfo.systemUptime - raisedAt < Self.raiseEchoWindow else {
            selfRaised.removeValue(forKey: id)
            return false
        }
        return true
    }

    /// The user has let go. The window has been off its tile for the length of the drag, so
    /// clearing `desired` is what makes `apply` write it into whichever tile it now owns —
    /// its own, if the drag never crossed another one. `apply` ends in `updateBorder`, which
    /// brings the focus border back now that the drag is over.
    ///
    /// An edge that was let go of moves the split first, so that the tile `apply` then writes
    /// is the frame the window already has, give or take the ratio clamp and the rounding in
    /// `frames(gaps:)` — and every neighbour is written once, into the space that is left. The
    /// frame is read here, after the fact, whichever way the drag ended: the mouse-up monitor,
    /// or a trailing notification that found the button already up. Nothing to move — a
    /// window with no neighbour on that axis, or a drag that turned out to be a move after all
    /// — falls through to the snap-back this always was.
    ///
    /// A float has no tile to snap back to, but it has a margin: `settleFloat` brings one that
    /// was dropped past `gaps_out` back inside it, and `apply` writes the result the way it
    /// writes any floating frame that differs from what the window has. The frame is read
    /// afresh rather than trusted to `floatingFrames`, which holds whatever the last Moved
    /// notification said — and the last one of a drag can arrive after the mouse-up.
    private func endDrag(_ id: WindowID, kind: DragMonitor.Kind, origin: Box?) {
        if workspaces.isFloating(id) {
            if let have = tracker.window(id)?.element.frame { workspaces.floatingFrames[id] = have }
            workspaces.settleFloat(id)
        } else if kind == .resize, let origin, let have = tracker.window(id)?.element.frame,
                  let gesture = ResizeGesture.delta(from: origin, to: have) {
            workspaces.resizeWindow(id, dx: gesture.dx, dy: gesture.dy, edges: gesture.edges)
        }
        desired.removeValue(forKey: id)
        corrections.removeValue(forKey: id)
        apply(refocus: false)
    }

    /// Everything that must happen before toe goes away, whichever way it is going: the Quit menu
    /// item, or SIGTERM, which is how `make run` replaces a running copy. There is no
    /// `applicationWillTerminate` — `NSApp.terminate` and `exit(0)` are both reached from here, so
    /// this is the one teardown path.
    private func shutDown() {
        // First, and before `unstashEverything` starts moving windows around: this is the one
        // write that matters, since it is the one a deliberate restart depends on.
        saveSession()
        unstashEverything()
        // A filtering tap left registered against a callback that is about to go away spins
        // WindowServer, so it is taken down deliberately rather than left to process death.
        dockSwipes.stop()
        hideBlocker.stop()
        // The four that would otherwise outlive toe: the window server keeps a symbolic hotkey
        // switched off until something switches it back on, and the reveal-desktop, edge-tiling
        // and Dock auto-hide preferences are written to the user's settings.
        SymbolicHotkeys.restoreAll()
        WallpaperClick.restore()
        EdgeTiling.restore()
        DockAutoHide.restore()
    }

    private func unstashEverything() {
        for window in tracker.windows.values where window.isStashed {
            window.isStashed = false
            if let frame = window.frameBeforeStash {
                WindowMover.setFrame(frame, element: window.element, pid: window.pid)
            }
        }
    }

    // MARK: - Session

    /// Puts back the layout the last run left behind.
    ///
    /// Before `tracker.start()`, deliberately: the applications are still running, so their
    /// windows come back through Accessibility over the second that follows, and the tree has
    /// to be waiting for them rather than built around them as they arrive. A window the
    /// snapshot placed is recognised in `windowAppeared` and left exactly where it was.
    private func restoreSession() {
        // Held until `settleSession`, whether or not there was anything to restore, so the
        // first snapshot of a fresh run is not taken mid-adoption either.
        isSettlingSession = true
        guard config.misc.restoreSession, let snapshot = SessionStore.load() else { return }

        let byKey = Dictionary(monitorKeys().map { ($0.value, $0.key) },
                               uniquingKeysWith: { first, _ in first })
        workspaces.restore(snapshot, monitorID: { byKey[$0] })

        let restored = workspaces.workspaces.values.reduce(0) { $0 + $1.windows.count }
        Log.info("session restored: \(restored) window(s) across "
                 + "\(workspaces.workspaces.values.filter { !$0.isEmpty }.count) workspace(s)")
    }

    /// Clears out whatever the snapshot named that has not turned up.
    ///
    /// The tracker sweeps each application at 0.15, 0.4, 0.8 and 1.5 seconds, because apps are
    /// frequently not AX-ready the instant they launch. Past the last of those, a window still
    /// missing is one that no longer exists — an application quit while toe was down — and
    /// dropping it collapses the tree around the gap the way losing it live would have. Until
    /// then a tile with nothing behind it costs nothing: `apply` skips every id the tracker
    /// does not know.
    private func settleSession() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            self.isSettlingSession = false
            if self.workspaces.reap(keeping: Set(self.tracker.windows.keys)) {
                self.apply(refocus: false)
            }
            self.saveSession()
        }
    }

    /// Debounced, because `apply` runs on every layout change and a focus change is a layout
    /// change as far as the snapshot is concerned. The write that actually matters is the one
    /// in `shutDown`; this is the one that covers the ways toe can go away without reaching it
    /// — a crash, or `kill -9`.
    private func scheduleSessionSave() {
        guard isManaging, !isSettlingSession, config.misc.restoreSession else { return }
        sessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSession() }
        sessionSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func saveSession() {
        sessionSave?.cancel()
        sessionSave = nil
        // Quitting while the session is still settling deliberately writes nothing: the file
        // already on disk is the good one, and what is in memory right now is half of it.
        guard isManaging, !isSettlingSession, config.misc.restoreSession else { return }

        let keys = monitorKeys()
        SessionStore.save(workspaces.snapshot(boot: SessionStore.bootToken,
                                              monitorKey: { keys[$0] }))
    }

    /// Turning the session off should not leave a stale layout on disk that toe will never
    /// read again.
    private func applySessionSetting() {
        guard !config.misc.restoreSession else { return }
        sessionSave?.cancel()
        sessionSave = nil
        SessionStore.clear()
    }

    /// A durable name for each live display, asked again every time rather than cached:
    /// `CGDirectDisplayID` is handed out per connection, so the mapping changes under us
    /// whenever a monitor is plugged or unplugged.
    private func monitorKeys() -> [UInt32: String] {
        var out: [UInt32: String] = [:]
        for monitor in workspaces.monitors {
            if let key = SessionStore.monitorKey(monitor.id) { out[monitor.id] = key }
        }
        return out
    }

    // MARK: - Dispatch

    private func focus(_ id: WindowID) {
        guard let window = tracker.window(id) else { return }
        workspaces.noteFocus(id)
        focusApplied = id
        // Before the focus, not after: this raises the tiles a float has stopped being
        // entitled to cover, and doing it afterwards would raise them over the very window
        // that is being focused.
        sinkUnfocusedFloats(workspaces.render())
        WindowMover.focus(window)
        updateBorder()
        refreshStatus()
    }

    func dispatch(_ command: Command) {
        switch command {
        case .moveFocus(let direction):
            if let target = workspaces.windowInDirection(direction) { focus(target) }

        case .swapWindow(let direction):
            if workspaces.swapWindow(direction) { apply(refocus: false) }

        case .moveWindow(let direction):
            if workspaces.moveWindow(direction) { apply(refocus: false) }

        case .workspace(let target):
            switchWorkspace(target)
            apply(refocus: true)

        case .moveToWorkspace(let n, let follow):
            workspaces.moveFocusedWindow(toWorkspace: n, follow: follow)
            apply(refocus: follow)

        case .killActive:
            guard let id = workspaces.focusedWindow, let window = tracker.window(id) else { return }
            WindowMover.close(window)

        case .toggleFloating:
            guard let id = workspaces.focusedWindow else { return }
            workspaces.toggleFloating(id)
            desired.removeValue(forKey: id)
            corrections.removeValue(forKey: id)
            apply(refocus: false)
            // A floating window belongs above the tiles. AX has no persistent always-on-top,
            // so raise it now; focusing it later raises it again.
            if workspaces.isFloating(id), let window = tracker.window(id) {
                WindowMover.focus(window)
                focusApplied = id
            }

        case .toggleSplit:
            guard let id = workspaces.focusedWindow,
                  let index = workspaces.workspaceIndex(of: id) else { return }
            workspaces.workspaces[index]?.layout.toggleSplit(id)
            apply(refocus: false)

        case .swapSplit:
            guard let id = workspaces.focusedWindow,
                  let index = workspaces.workspaceIndex(of: id) else { return }
            workspaces.workspaces[index]?.layout.swapSplit(id)
            apply(refocus: false)

        case .resizeActive(let dx, let dy), .growActive(let dx, let dy):
            // A float grows in place and `apply` writes the new frame the way it writes any
            // floating one — on a real difference, outside `desired`.
            guard let id = workspaces.focusedWindow else { return }
            let moved: Bool
            if case .growActive = command {
                moved = workspaces.growWindow(id, dx: dx, dy: dy)
            } else {
                moved = workspaces.resizeWindow(id, dx: dx, dy: dy)
            }
            guard moved else {
                // The one command whose doing nothing is easy to mistake for not working: the
                // only window on a workspace has no split to move, and neither has a
                // side-by-side pair asked for the vertical axis. Say so where `log stream`
                // can see it.
                Log.info("\(CommandLabel.describe(command)): nothing to move for window \(id) — no split on that axis")
                return
            }
            apply(refocus: false)

        case .exec(let commandLine):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", commandLine]
            try? process.run()

        case .reload:
            // Forced: this key is pressed precisely when something needs to happen — most often
            // to re-tile a window an app has pushed out of place — and `toe.toml` will not have
            // changed, so the unchanged-bytes early-out would make it do nothing at all.
            loadConfig(force: true)

        case .menu(let route):
            // `styleMenu()` re-reads the themes directory here rather than relying on the last
            // reload, which is what makes a theme folder you created a moment ago appear the
            // first time you look. It is a directory listing; nothing is opened.
            quickMenu.toggle(route: route, config: config,
                             usable: workspaces.monitor(id: workspaces.focusedMonitorID)?.usable,
                             style: styleMenu())

        case .quit:
            shutDown()
            NSApp.terminate(nil)

        case .theme(let slug):
            setTheme(slug)

        case .removeTheme(let slug):
            removeTheme(slug)

        case .background(let file):
            setBackground(file)

        case .nextBackground:
            guard let next = Backgrounds.next(after: currentBackground, in: backgrounds) else {
                return
            }
            setBackground(next)
        }
    }
}
