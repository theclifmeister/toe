import AppKit
import ToeCore

/// The quick menu's two halves that need `Coordinator`'s state: the context its tree is built from,
/// and the side effects its rows ask for. In an extension because Coordinator.swift is long enough
/// already, and this is one concern.
extension Coordinator {

    /// Gathered afresh every time the menu opens — nothing here is maintained while it is closed,
    /// the same contract `StatusItem.menuNeedsUpdate` keeps.
    func menuContext() -> MenuContext {
        MenuContext(workspaces: workspaceSummaries(),
                    focusedWindow: workspaces.focusedWindow,
                    focusedWorkspace: workspaces.focusedWorkspaceIndex,
                    config: config,
                    version: Coordinator.version,
                    startAtLogin: StartAtLogin.state)
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    func perform(_ action: MenuAction) {
        switch action {
        case .command(let command):
            dispatch(command)

        case .revealWindow(let id):
            reveal(id)

        case .applyBorderTheme(let theme):
            writeConfig([
                .init(table: "border", key: "active_start", value: .string(theme.activeStart)),
                .init(table: "border", key: "active_end", value: .string(theme.activeEnd)),
            ])

        case .applyGaps(let inner, let outer):
            writeConfig([
                .init(table: "general", key: "gaps_in", value: .int(inner)),
                .init(table: "general", key: "gaps_out", value: .int(outer)),
            ])

        case .setBorderEnabled(let enabled):
            writeConfig([.init(table: "border", key: "enabled", value: .bool(enabled))])

        case .reveal(.configFile):
            NSWorkspace.shared.open(Coordinator.configURL)

        case .reveal(.configFolder):
            NSWorkspace.shared.activateFileViewerSelecting([Coordinator.configURL])

        case .reveal(.accessibilitySettings):
            Coordinator.openAccessibilitySettings()

        case .setStartAtLogin(let enabled):
            StartAtLogin.set(enabled)

        case .removeLegacyLaunchAgent:
            StartAtLogin.removeLegacyLaunchAgent()

        case .system(let system):
            // No second confirmation here. `QuickMenuController` has already pushed the
            // Cancel/Confirm level for anything that `needsConfirmation`, and its Confirm row is
            // what sent this — asking again with an NSAlert would be the same question twice.
            SystemActions.perform(system)

        case .restartToe:
            unstashEverything()
            SystemActions.relaunch()

        case .quitToe:
            quit()

        case .openURL(let string):
            guard let url = URL(string: string) else { return }
            NSWorkspace.shared.open(url)

        case .copyToClipboard(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)

        case .launchApp(let path):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            // Activate the running instance rather than spawning a duplicate. Note this launches
            // an app; it does not open a new window — which is exactly why the shipped
            // `super-enter` binding goes through AppleScript instead.
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: configuration) { _, error in
                if let error { Log.error("launch failed: \(error.localizedDescription)") }
            }
        }
    }

    /// Writes the user's own config and lets `ConfigWatcher` reload it.
    ///
    /// Deliberately *not* followed by `loadConfig()`. That ends in `desired.removeAll()` plus a full
    /// `apply`, which rewrites every window's frame through the Accessibility API — doing it twice
    /// inside the watcher's debounce would flicker every tiled window for the sake of a border
    /// colour. One write, one reload.
    ///
    /// Two honest properties, both of which Omarchy's own theme switching shares: if the file is
    /// open in an editor with unsaved changes, that editor's next save wins; and there is no undo
    /// beyond choosing something else.
    private func writeConfig(_ edits: [TOMLEdit.Edit]) {
        let url = Coordinator.configURL
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? Config.defaultTOML
        let updated = TOMLEdit.apply(edits, to: existing)
        guard updated != existing else { return }
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.error("could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
