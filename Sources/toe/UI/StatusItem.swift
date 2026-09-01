import AppKit
import ToeCore

/// One application's presence on a workspace.
struct AppSummary {
    let name: String
    let windowCount: Int
    let icon: NSImage?
    /// Selecting the row focuses this window.
    let representativeWindow: WindowID
}

struct WorkspaceSummary {
    let index: Int
    /// Shown on the monitor that currently has focus.
    let isFocused: Bool
    /// Shown on some monitor — with several displays, more than one workspace is visible.
    let isVisible: Bool
    let monitorName: String?
    let apps: [AppSummary]

    var isEmpty: Bool { apps.isEmpty }
}

/// The menu bar item. toe is an `LSUIElement`, so this is its only visible surface.
///
/// The title is the workspace strip — occupied workspaces, with the focused one picked out —
/// and the menu breaks each workspace down into the applications living on it.
final class StatusItem: NSObject, NSMenuDelegate {

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    /// Rebuilt on demand when the menu opens, so the app list is never stale and toe does no
    /// work maintaining it while the menu is closed.
    var workspaceProvider: (() -> [WorkspaceSummary])?
    var onSelectWorkspace: ((Int) -> Void)?
    var onSelectWindow: ((WindowID) -> Void)?
    var onReload: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onQuit: (() -> Void)?

    private var warnings: [String] = []
    private var accessibilityGranted = false
    private var showMonitorNames = false

    private let regular = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let emphasised = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)

    override init() {
        super.init()
        menu.delegate = self
        item.menu = menu
        item.button?.title = "toe"
    }

    /// Cheap: only the title strip is recomputed. The menu rebuilds itself when opened.
    func update(workspaces: [WorkspaceSummary], warnings: [String], accessibilityGranted: Bool,
                showMonitorNames: Bool) {
        self.warnings = warnings
        self.accessibilityGranted = accessibilityGranted
        self.showMonitorNames = showMonitorNames
        item.button?.attributedTitle = title(for: workspaces)
        item.button?.toolTip = accessibilityGranted
            ? "toe — workspace \(workspaces.first { $0.isFocused }?.index ?? 1)"
            : "toe needs Accessibility permission"
    }

    // MARK: - The workspace strip

    private func title(for workspaces: [WorkspaceSummary]) -> NSAttributedString {
        guard accessibilityGranted else {
            return NSAttributedString(string: "toe !", attributes: [
                .font: emphasised, .foregroundColor: NSColor.systemOrange,
            ])
        }

        // Empty workspaces are hidden, so the strip stays as short as what you are actually
        // using — but the focused one is always there, even when it is empty.
        let shown = workspaces.filter { !$0.isEmpty || $0.isVisible }
        guard !shown.isEmpty else {
            return NSAttributedString(string: "toe", attributes: [.font: regular])
        }

        let strip = NSMutableAttributedString()
        for workspace in shown {
            if strip.length > 0 {
                strip.append(NSAttributedString(string: " ", attributes: [.font: regular]))
            }
            let attributes: [NSAttributedString.Key: Any]
            if workspace.isFocused {
                attributes = [.font: emphasised, .foregroundColor: NSColor.labelColor]
            } else if workspace.isVisible {
                // Showing on another display.
                attributes = [.font: emphasised, .foregroundColor: NSColor.secondaryLabelColor]
            } else {
                attributes = [.font: regular, .foregroundColor: NSColor.tertiaryLabelColor]
            }
            strip.append(NSAttributedString(string: "\(workspace.index)", attributes: attributes))
        }
        return strip
    }

    // MARK: - The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !accessibilityGranted {
            add(to: menu, "Grant Accessibility permission…", #selector(openAccessibility))
            menu.addItem(.separator())
        }

        let workspaces = (workspaceProvider?() ?? []).filter { !$0.isEmpty || $0.isVisible }
        if workspaces.isEmpty {
            menu.addItem(disabled("No windows"))
        }

        for workspace in workspaces {
            let heading = NSMenuItem(title: headingTitle(workspace),
                                     action: #selector(selectWorkspace(_:)), keyEquivalent: "")
            heading.target = self
            heading.tag = workspace.index
            heading.state = workspace.isFocused ? .on : (workspace.isVisible ? .mixed : .off)
            heading.attributedTitle = NSAttributedString(
                string: headingTitle(workspace),
                attributes: [.font: NSFont.menuFont(ofSize: 13).bold])
            menu.addItem(heading)

            if workspace.isEmpty {
                let empty = disabled("empty")
                empty.indentationLevel = 1
                menu.addItem(empty)
                continue
            }

            for app in workspace.apps {
                let label = app.windowCount > 1 ? "\(app.name)  ×\(app.windowCount)" : app.name
                let entry = NSMenuItem(title: label, action: #selector(selectWindow(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.indentationLevel = 1
                entry.representedObject = app.representativeWindow
                if let icon = app.icon {
                    let sized = icon.copy() as! NSImage
                    sized.size = NSSize(width: 16, height: 16)
                    entry.image = sized
                }
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())

        if warnings.isEmpty {
            menu.addItem(disabled("Config loaded"))
        } else {
            let header = NSMenuItem(title: "\(warnings.count) config problem(s)",
                                    action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for warning in warnings {
                submenu.addItem(NSMenuItem(title: warning, action: nil, keyEquivalent: ""))
            }
            menu.setSubmenu(submenu, for: header)
            menu.addItem(header)
        }

        menu.addItem(.separator())
        add(to: menu, "Reload config", #selector(reload), key: "r")
        add(to: menu, "Open config…", #selector(openConfig), key: "o")
        menu.addItem(.separator())
        add(to: menu, "Quit toe", #selector(quit), key: "q")
    }

    private func headingTitle(_ workspace: WorkspaceSummary) -> String {
        var title = "Workspace \(workspace.index)"
        if showMonitorNames, workspace.isVisible, let monitor = workspace.monitorName {
            title += " — \(monitor)"
        }
        return title
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    // MARK: - Actions

    @objc private func selectWorkspace(_ sender: NSMenuItem) { onSelectWorkspace?(sender.tag) }
    @objc private func selectWindow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? WindowID else { return }
        onSelectWindow?(id)
    }
    @objc private func reload() { onReload?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func openAccessibility() { onOpenAccessibility?() }
    @objc private func quit() { onQuit?() }
}

private extension NSFont {
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
