import Foundation

/// One thing on the bar — Omarchy's `WidgetButton`, as a value.
///
/// Every widget on Omarchy's bar is a label centred in a slot the bar's height, and nothing
/// else: no box, no border, no background of its own. What varies is the label, how wide the
/// slot is, how faint the label is drawn and which colour it takes, and that is all this
/// carries. The providers in `toe` make these; `BarLayout.place` lays them out; `BarView` draws
/// whatever it is handed. None of the three knows what a battery is.
public struct BarItem: Equatable, Sendable {

    /// Omarchy's three bar regions. `left` and `right` are rows inset from the screen edge;
    /// `center` is anchored — see `BarLayout.place`.
    public enum Section: Equatable, Sendable {
        case left, center, right
    }

    /// Which widget, in Omarchy's names, so a click can be turned back into an action. A
    /// workspace slot carries its index because there are ten of them and one kind.
    public enum Kind: Hashable, Sendable {
        case menu
        case workspace(Int)
        /// What stands where the workspaces go until Accessibility is granted: there is no
        /// strip to draw without it, and no way to grant it from the bar but a click here —
        /// the menu bar item's `toe !`, moved.
        case accessibility
        case doNotDisturb
        case clock
        case keyboardLayout
        case bluetooth
        case network
        case audio
        case monitor
        case power
    }

    /// The three sizes `Style.font` gives the bar, as roles rather than numbers: the number
    /// depends on `[bar] font_size` and is `BarMetrics`'s to work out.
    public enum Font: Equatable, Sendable {
        /// `Style.font.body` — the clock, the workspace digits.
        case body
        /// `Style.font.caption` — the indicators and the keyboard layout.
        case caption
        /// `Style.bar.iconFont` — every glyph in an icon slot.
        case icon
    }

    /// How wide the slot is.
    public enum Slot: Equatable, Sendable {
        /// `WidgetButton`'s own rule: the label plus a margin either side, never under 12.
        case padded(margin: Double)
        /// `BarIconButton`'s 27, `BarIndicator`'s 21 and a workspace's 20 — the label's width
        /// does not enter into it.
        case fixed(Double)
    }

    public let kind: Kind
    public let section: Section
    public let text: String
    public let font: Font
    public let slot: Slot
    /// `WidgetButton.opacity`: 1 for a live widget, 0.5 for an empty workspace, 0.45 for a
    /// dimmed indicator, and 0 for a concealed one — which takes no room either, see
    /// `BarLayout.place`.
    public let opacity: Double
    /// Painted in `[bar] active` rather than the foreground — Omarchy's `urgent`, which on the
    /// bar is the network widget behind a captive portal.
    public let active: Bool
    public let tooltip: String
    /// Room after this item and before the next in its section — Omarchy's rows have no
    /// spacing, so this is 0 except inside the workspace strip, whose slots are `space(1)`
    /// apart with `spaceReal(1.5)` after the last.
    public let gapAfter: Double

    public init(kind: Kind, section: Section, text: String, font: Font = .body,
                slot: Slot = .padded(margin: BarMetrics.defaultMargin), opacity: Double = 1,
                active: Bool = false, tooltip: String = "", gapAfter: Double = 0) {
        self.kind = kind
        self.section = section
        self.text = text
        self.font = font
        self.slot = slot
        self.opacity = opacity
        self.active = active
        self.tooltip = tooltip
        self.gapAfter = gapAfter
    }

    /// Concealed: drawn at nothing and given no room.
    public var isHidden: Bool { opacity <= 0 }
}

/// Omarchy's `Style.bar` and the spacing tokens the bar uses, at the user's size.
///
/// Upstream every one of these scales with `[font] base-size` through `Style.barToken` and
/// `Style.space`, and the bar's height with it. toe splits that in two: `[bar] height` is the
/// user's, and the slots and margins scale with the height — so a taller bar has proportionally
/// wider slots, as it would upstream — while `[bar] font_size` sets the type on its own. The
/// numbers are `Style.qml`'s at its defaults: 26 tall, 27 for an icon slot, 21 for a status
/// indicator, 20 for a workspace, 8 in from the screen edge.
public struct BarMetrics: Equatable, Sendable {
    /// `Style.bar.sizeHorizontal` at base-size 12.
    public static let referenceHeight: Double = 26
    /// `WidgetButton.horizontalMargin`.
    public static let defaultMargin: Double = 8.5

    public var height: Double
    public var fontSize: Double

    public init(height: Double = referenceHeight, fontSize: Double = 12) {
        self.height = height
        self.fontSize = fontSize
    }

    /// `Style.fontScale`, with the height standing in for the base size.
    var scale: Double { height / Self.referenceHeight }

    /// `Style.barToken`: the token at 12px, scaled and rounded, never under 1.
    func barToken(_ base: Double) -> Double { max(1, (base * scale).rounded()) }
    /// `Style.space`: the same for a spacing token.
    func space(_ base: Double) -> Double { max(1, (base * scale).rounded()) }
    /// `Style.spaceReal`: unrounded, for the fractional gaps.
    func spaceReal(_ base: Double) -> Double { base * scale }

    public var iconSlot: Double { barToken(27) }
    public var statusSlot: Double { barToken(21) }
    public var workspaceSlot: Double { space(20) }
    /// `Style.space(1)` between workspace slots, `spaceReal(1.5)` after the last.
    public var workspaceGap: Double { space(1) }
    public var workspaceTrailingGap: Double { spaceReal(1.5) }
    /// `anchors.leftMargin: Style.space(8)` on the left row, the same on the right.
    public var edgeMargin: Double { space(8) }

    /// `Style.font`'s tokens, derived from the body size as `fontPx` derives them: caption is
    /// 0.833 of it and the icon font 13/12 of it, rounded, never under 1.
    public func pointSize(_ font: BarItem.Font) -> Double {
        switch font {
        case .body:    return max(1, fontSize.rounded())
        case .caption: return max(1, (fontSize * 0.833).rounded())
        case .icon:    return max(1, (fontSize * 13 / 12).rounded())
        }
    }

    /// The width of a slot holding a label that measured `labelWidth` wide.
    public func slotWidth(_ slot: BarItem.Slot, labelWidth: Double) -> Double {
        switch slot {
        case .fixed(let width):    return width
        case .padded(let margin):  return max(12, labelWidth + spaceReal(margin) * 2)
        }
    }
}

/// The items on the bar, built the way Omarchy's widgets build them — so the numbers live here,
/// next to `BarMetrics`, and the providers in `toe` supply only what the system told them.
public enum BarItems {

    /// `Workspaces.qml`: a 20-wide slot per strip item, the focused one a rounded square, empty
    /// ones at half opacity, `space(1)` between and `spaceReal(1.5)` after the last.
    ///
    /// `WorkspaceStrip.items` decides which workspaces earn a slot and what each is labelled; this
    /// only dresses them. `visible` — on screen on another display — draws the digit at full
    /// opacity, which is where toe's addition to Omarchy's two states lands on a bar with no
    /// outline to give it: the workspace is in use, and that is what full opacity says.
    public static func workspaces(_ items: [WorkspaceStrip.Item], metrics: BarMetrics) -> [BarItem] {
        items.enumerated().map { offset, item in
            let last = offset == items.count - 1
            return BarItem(kind: .workspace(item.index), section: .left,
                           text: item.marker == .focused ? Glyphs.workspace : item.label,
                           font: .body, slot: .fixed(metrics.workspaceSlot),
                           opacity: item.dim && item.marker != .focused ? 0.5 : 1,
                           tooltip: "Workspace \(item.index)",
                           gapAfter: last ? metrics.workspaceTrailingGap : metrics.workspaceGap)
        }
    }

    /// `menu/BarWidget.qml`: the mark, at a 7.5 margin. toe's T is a path rather than a glyph,
    /// so there is no label to measure: the view says how wide it draws the mark and the slot
    /// is that plus the margins, which is what `WidgetButton` would have made of a label that
    /// wide. `text` is empty, and the view draws the mark for the kind.
    public static func menu(markWidth: Double, metrics: BarMetrics) -> BarItem {
        BarItem(kind: .menu, section: .left, text: "", font: .body,
                slot: .fixed(max(12, markWidth + metrics.spaceReal(7.5) * 2)), tooltip: "Menu")
    }

    /// `toe !` where the strip would be, in `active` — the one thing on the bar that is a
    /// problem rather than a state, and the colour Omarchy gives a widget calling attention to
    /// itself. The default margin, since it is a label like the clock.
    public static func accessibility() -> BarItem {
        BarItem(kind: .accessibility, section: .left, text: "toe !", font: .body,
                active: true, tooltip: "toe needs Accessibility permission — click to grant it")
    }

    /// `panels/clock/BarWidget.qml`: the label at an 8.75 margin — upstream's number, a hair
    /// over the default.
    public static func clock(_ label: String) -> BarItem {
        BarItem(kind: .clock, section: .center, text: label, font: .body,
                slot: .padded(margin: 8.75), tooltip: "Right-click to toggle format")
    }

    /// `BarIndicator`: a caption-sized glyph in the 21 status slot, full when its mode is on and
    /// otherwise 0.45 while the centre is hovered and nothing at all when it is not.
    public static func indicator(_ kind: BarItem.Kind, glyph: String, on: Bool, revealed: Bool,
                                 tooltip: String, metrics: BarMetrics) -> BarItem {
        BarItem(kind: kind, section: .center, text: glyph, font: .caption,
                slot: .fixed(metrics.statusSlot),
                opacity: on ? 1 : (revealed ? 0.45 : 0), tooltip: tooltip)
    }

    /// `KeyboardLayout.qml`: the short label at caption size and a 6 margin.
    public static func keyboardLayout(_ label: String, full: String) -> BarItem {
        BarItem(kind: .keyboardLayout, section: .center, text: label, font: .caption,
                slot: .padded(margin: 6), tooltip: full)
    }

    /// `BarIconButton`: a glyph in the 27 icon slot — every widget on the right. `slots` is for
    /// the power widget with its percentage showing, which takes two.
    public static func icon(_ kind: BarItem.Kind, glyph: String, active: Bool = false,
                            tooltip: String = "", slots: Int = 1, metrics: BarMetrics) -> BarItem {
        BarItem(kind: kind, section: .right, text: glyph, font: .icon,
                slot: .fixed(metrics.iconSlot * Double(max(1, slots))),
                active: active, tooltip: tooltip)
    }
}
