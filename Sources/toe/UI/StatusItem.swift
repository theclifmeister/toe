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

    var stripState: WorkspaceStrip.State {
        .init(index: index, isFocused: isFocused, isVisible: isVisible, isEmpty: isEmpty)
    }
}

/// The menu bar item. toe is an `LSUIElement`, so this is its only visible surface.
///
/// The title is the workspace strip in Omarchy's waybar styling — the focused workspace is
/// a filled rounded square, every other one its own digit — and the menu breaks each
/// workspace down into the applications living on it. Clicking a workspace switches to it,
/// as Omarchy's `on-click: activate` does; anywhere else opens the menu.
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

    /// waybar's `persistent-workspaces` — how many workspaces keep a slot when empty.
    var persistentWorkspaces = WorkspaceStrip.defaultPersistent

    /// What the strip currently draws, and how wide each item came out — together they turn
    /// a click position back into a workspace.
    private var stripItems: [WorkspaceStrip.Item] = []
    private var stripWidths: [Double] = []

    // Omarchy's bar is JetBrainsMono Nerd Font at 12px with `padding: 0 6px; margin: 0 1.5px`,
    // i.e. a ~15px slot per workspace. These are its equivalents at menu bar size.
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let gap: CGFloat = 7
    private let markerSide: CGFloat = 8
    private let markerRadius: CGFloat = 2.5

    /// Omarchy dims empty workspaces with `opacity: 0.5`. The menu bar is translucent over
    /// whatever wallpaper is behind it, and half opacity there is too faint to read, so toe
    /// dims less far.
    ///
    /// Built from a dynamic provider rather than `secondaryLabelColor` so it resolves when it
    /// is drawn, against the menu bar's own appearance — which is not always the app's, since
    /// macOS darkens the menu bar to suit the desktop picture.
    private static let dimLabelColor = NSColor(name: "toeDimLabel") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.7)
    }

    override init() {
        super.init()
        menu.delegate = self
        item.button?.title = "toe"
        item.button?.target = self
        item.button?.action = #selector(buttonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Cheap: only the title strip is recomputed. The menu rebuilds itself when opened.
    func update(workspaces: [WorkspaceSummary], warnings: [String], accessibilityGranted: Bool,
                showMonitorNames: Bool) {
        self.warnings = warnings
        self.accessibilityGranted = accessibilityGranted
        self.showMonitorNames = showMonitorNames
        item.button?.attributedTitle = title(for: workspaces)

        // The focused workspace is drawn as a square rather than a digit, so the title on
        // its own no longer reads as anything — spell it out for VoiceOver.
        let described = accessibilityGranted
            ? "toe — workspace \(workspaces.first { $0.isFocused }?.index ?? 1)"
            : "toe needs Accessibility permission"
        item.button?.toolTip = described
        item.button?.setAccessibilityLabel(described)
    }

    // MARK: - The workspace strip

    private func title(for workspaces: [WorkspaceSummary]) -> NSAttributedString {
        stripItems = []
        stripWidths = []

        guard accessibilityGranted else {
            return NSAttributedString(string: "toe !", attributes: [
                .font: font, .foregroundColor: NSColor.systemOrange,
            ])
        }

        let items = WorkspaceStrip.items(for: workspaces.map(\.stripState),
                                         persistent: persistentWorkspaces)
        guard !items.isEmpty else {
            return NSAttributedString(string: "toe", attributes: [.font: font])
        }

        let strip = NSMutableAttributedString()
        for item in items {
            if strip.length > 0 { strip.append(spacer) }
            strip.append(piece(for: item))
            stripItems.append(item)
            stripWidths.append(Double(width(of: item)))
        }
        return strip
    }

    /// A fixed `gap` of empty space, kerned rather than padded so its width is exactly known.
    private var spacer: NSAttributedString {
        let space = NSAttributedString(string: " ", attributes: [.font: font]).size().width
        return NSAttributedString(string: " ", attributes: [.font: font, .kern: gap - space])
    }

    private func piece(for item: WorkspaceStrip.Item) -> NSAttributedString {
        switch item.marker {
        case .digit:
            return NSAttributedString(string: item.label, attributes: [
                .font: font,
                .foregroundColor: item.dim ? Self.dimLabelColor : NSColor.labelColor,
            ])
        case .focused, .visible:
            let attachment = NSTextAttachment()
            attachment.image = marker(filled: item.marker == .focused, dim: item.dim,
                                      side: markerSide)
            // Centre the square on the digits' cap height rather than the baseline.
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - markerSide) / 2,
                                       width: markerSide, height: markerSide)
            return NSAttributedString(attachment: attachment)
        }
    }

    private func width(of item: WorkspaceStrip.Item) -> CGFloat {
        item.marker == .digit
            ? NSAttributedString(string: item.label, attributes: [.font: font]).size().width
            : markerSide
    }

    /// `nf-md-square_rounded`, which is what Omarchy marks the active workspace with — drawn
    /// rather than set, so it needs no Nerd Font installed. The drawing handler runs at draw
    /// time, so the colour resolves against whichever appearance the menu bar is in.
    private func marker(filled: Bool, dim: Bool, side: CGFloat,
                        canvas: CGFloat? = nil) -> NSImage {
        let box = canvas ?? side
        let radius = markerRadius * (side / markerSide)
        let image = NSImage(size: NSSize(width: box, height: box), flipped: false) { rect in
            let colour = dim ? Self.dimLabelColor : NSColor.labelColor
            let square = NSRect(x: (rect.width - side) / 2, y: (rect.height - side) / 2,
                                width: side, height: side)
            if filled {
                colour.setFill()
                NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius).fill()
            } else {
                colour.setStroke()
                let path = NSBezierPath(roundedRect: square.insetBy(dx: 0.75, dy: 0.75),
                                        xRadius: radius - 0.75, yRadius: radius - 0.75)
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
        // Redraw on every use, so a light/dark switch cannot leave a stale square behind.
        image.cacheMode = .never
        return image
    }

    // MARK: - Clicks

    /// The menu is attached only while it is up, so the rest of the time this action runs and
    /// the strip stays clickable.
    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseUp,
              !event.modifierFlags.contains(.control)
        else { return popUpMenu() }

        let x = sender.convert(event.locationInWindow, from: nil).x
        if let hit = WorkspaceStrip.hit(x: Double(x), widths: stripWidths,
                                        gap: Double(gap), buttonWidth: Double(sender.bounds.width)) {
            onSelectWorkspace?(stripItems[hit].index)
        } else {
            // The padding at either end, or a strip with no workspaces in it.
            popUpMenu()
        }
    }

    private func popUpMenu() {
        item.menu = menu                 // menuNeedsUpdate fires here
        item.button?.performClick(nil)   // blocks until the menu closes
        item.menu = nil
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
            // The same square the strip uses, so the two surfaces read as one thing.
            if workspace.isVisible {
                heading.image = marker(filled: workspace.isFocused, dim: workspace.isEmpty,
                                       side: 9, canvas: 12)
            }
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
