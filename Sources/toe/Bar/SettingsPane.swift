import AppKit

/// The System Settings panes the bar's widgets open — Omarchy's panels, with the Mac's own
/// window standing in for each. `NSWorkspace.open`, not `exec`: opening a pane is not a
/// command and does not want the `[cli] allow_exec` gate in front of it.
///
/// The URLs are the `x-apple.systempreferences:` scheme's extension identifiers, which is what
/// System Settings has answered to since Ventura; checked on macOS 27 for #171.
enum SettingsPane: String {
    case accessibility = "com.apple.preference.security?Privacy_Accessibility"
    case battery = "com.apple.Battery-Settings-extension"
    case displays = "com.apple.Displays-Settings.extension"
    case sound = "com.apple.Sound-Settings.extension"
    case wifi = "com.apple.wifi-settings-extension"
    case bluetooth = "com.apple.BluetoothSettings"
    case keyboard = "com.apple.Keyboard-Settings.extension"

    var url: URL { URL(string: "x-apple.systempreferences:" + rawValue)! }

    func open() {
        NSWorkspace.shared.open(url)
    }
}
