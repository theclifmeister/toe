import Foundation

public struct BorderConfig: Equatable {
    public var enabled: Bool = true
    public var width: Double = 2
    /// Omarchy's `col.active_border` gradient.
    public var activeStart: String = "#33ccffee"
    public var activeEnd: String = "#00ff99ee"
    public var angle: Double = 45
    /// Negative follows the window's own corner radius — the window server is asked per
    /// window, falling back to the system value — 0 is square, positive is an explicit value
    /// in points.
    public var radius: Double = -1
    public init() {}
}

/// The menu bar's workspace strip.
public struct BarConfig: Equatable {
    /// waybar's `persistent-workspaces`: how many workspaces keep a slot whether or not
    /// anything is on them. 0 shows only the ones in use.
    public var persistentWorkspaces: Int = WorkspaceStrip.defaultPersistent
    public init() {}
}

/// How big a window is when it leaves the tiling tree.
public struct FloatingSize: Equatable {
    /// Fraction of the monitor's usable width and height, at the first stop of the cycle.
    public var width: Double = 0.70
    public var height: Double = 0.80
    /// The second stop: pressing `togglefloating` again on a window that already floats grows
    /// it to this instead of tiling it, and only the press after that puts it back in the tree.
    public var largeWidth: Double = 0.80
    public var largeHeight: Double = 0.90
    /// Widest the window may be relative to its own height. On an ultrawide, 70% of the
    /// width is a letterbox; capping the ratio keeps a floating window a shape you would
    /// have picked by hand, on any display.
    public var maxAspectRatio: Double = 1.6
    public init() {}

    /// How many floating sizes `togglefloating` walks through before it tiles the window.
    public static let stages = 2

    /// The fractions stage 1 and stage 2 use. Anything outside that range is the nearest end,
    /// so a stage that has drifted — a snapshot from a build with more of them — still lands
    /// on a real size.
    public func fractions(stage: Int) -> (width: Double, height: Double) {
        stage >= 2 ? (largeWidth, largeHeight) : (width, height)
    }
}

/// Trackpad gestures toe takes off macOS's hands.
public struct GestureConfig: Equatable {
    /// Swallow the Dock's swipe gestures — Mission Control, App Exposé and the sideways Spaces
    /// switch — before the window server acts on them. Keyed off the gesture's event type rather
    /// than a finger count, so it covers the three-finger setting as well as the four-finger one.
    public var swallowDockSwipes: Bool = true
    public init() {}
}

/// macOS behaviours that pull windows out from under the layout. Hyprland's catch-all table.
public struct MiscConfig: Equatable {
    /// `Ctrl`+`↑` and `Ctrl`+`↓` open the same Mission Control and App Exposé the vertical swipe
    /// does, and a symbolic hotkey is resolved inside the window server, so the tap cannot reach
    /// them.
    public var disableExposeShortcuts: Bool = true
    /// A click on bare wallpaper sweeps every window off the sides of the screen, tiles and the
    /// off-screen stash alike, and macOS decides that inside WindowManager rather than from an
    /// event any tap could swallow — so it is switched off through its preference instead.
    public var disableWallpaperClick: Bool = true
    /// `⌘H` takes an application's windows out of the layout with no way to reach them again.
    public var preventHiding: Bool = true
    /// Whether the layout is written to disk and put back on the next launch. See
    /// `SessionSnapshot`; off means toe starts from an empty first workspace every time and
    /// leaves nothing behind in `~/.local/state/toe`.
    public var restoreSession: Bool = true
    public init() {}
}

/// A window that should float instead of joining the dwindle tree.
public struct FloatRule: Equatable {
    /// Bundle identifier. `*` matches any run of characters.
    public var app: String?
    /// Case-insensitive substring of the window title.
    public var title: String?

    public init(app: String? = nil, title: String? = nil) {
        self.app = app
        self.title = title
    }

    public func matches(bundleID: String?, title windowTitle: String?) -> Bool {
        if let app {
            guard let bundleID, Self.glob(app.lowercased(), matches: bundleID.lowercased()) else { return false }
        }
        if let t = self.title {
            guard let windowTitle, windowTitle.lowercased().contains(t.lowercased()) else { return false }
        }
        return app != nil || title != nil
    }

    static func glob(_ pattern: String, matches subject: String) -> Bool {
        guard pattern.contains("*") else { return pattern == subject }
        let parts = pattern.components(separatedBy: "*")
        var cursor = subject.startIndex
        for (i, part) in parts.enumerated() where !part.isEmpty {
            guard let found = subject.range(of: part, range: cursor..<subject.endIndex) else { return false }
            if i == 0 && found.lowerBound != subject.startIndex { return false }
            cursor = found.upperBound
        }
        if let last = parts.last, !last.isEmpty { return subject.hasSuffix(last) }
        return true
    }
}

public struct Config: Equatable {
    public var superKey: Modifiers = .option
    public var gaps: Gaps = Gaps(inner: 5, outer: 10)
    public var dwindle: DwindleOptions = DwindleOptions()
    public var border: BorderConfig = BorderConfig()
    public var bar: BarConfig = BarConfig()
    public var floating: FloatingSize = FloatingSize()
    public var gestures: GestureConfig = GestureConfig()
    public var misc: MiscConfig = MiscConfig()
    public var bindings: [Binding] = []
    public var floatRules: [FloatRule] = Config.defaultFloatRules
    /// Non-fatal problems (a binding that would not parse, an unknown key). Surfaced in the
    /// menu bar item rather than thrown, so one typo never leaves you without a keyboard.
    public var warnings: [String] = []

    public init() {}

    /// The ways out, bound in code so that they exist whether or not the config file mentions
    /// them. Every other setting already works this way — `gaps`, `border`, `dwindle` and the
    /// rest all default here and let the file override — and bindings were the one exception,
    /// living only in the template written on first run. That gap strands anyone who installed
    /// before a binding was introduced: their config is never rewritten, so the menu bar item
    /// losing its menu left them with no way to quit toe but `pkill`.
    ///
    /// Deliberately only the escape hatches. A fallback that covered every binding would be a
    /// second config competing with yours; these three exist so that a config which forgot them
    /// cannot leave you stuck, in the same spirit as keeping the last good config when a new one
    /// will not parse.
    public static let fallbackBindings: [(spec: String, command: Command)] = [
        ("super-comma", .editConfig),
        ("super-shift-r", .reload),
        ("super-shift-q", .quit),
    ]

    public static let defaultFloatRules: [FloatRule] = [
        FloatRule(app: "com.apple.systempreferences"),
        FloatRule(app: "com.apple.finder", title: "Copy"),
        FloatRule(app: "com.1password.1password"),
        FloatRule(app: "com.raycast.macos"),
        FloatRule(app: "com.apple.ActivityMonitor"),
    ]

    /// The whole default config, also written to disk on first run.
    public static let defaultTOML: String = defaultConfigText

    public static func makeDefault() -> Config {
        // The shipped default is guaranteed to parse; fall back to code defaults if it ever
        // does not, so toe still starts.
        (try? Config.parse(defaultTOML)) ?? Config()
    }

    /// One number from the config, or nil — with a warning appended — when it is not a finite
    /// value inside `range`.
    ///
    /// TOML spells `nan` and `inf`, and Swift's `Double(_: String)` accepts them as readily as
    /// it accepts `0x1p10`, so without a check here a single `gaps_in = nan` reaches the
    /// layout and three things go wrong at once. `Box` is `Equatable`, so every comparison
    /// against a NaN coordinate is false: toe decides the window is in the wrong place and
    /// re-writes its frame on every render, forever. The correction budget that notices a
    /// window fighting the layout compares the same way, so it never resets either. And the
    /// NaN geometry is written into other applications over Accessibility, where reading it
    /// back into an `NSWindow.setFrame` — which the border overlay does — traps.
    ///
    /// `[bar]` and `[floating]` were already range-checked. This is the same treatment for
    /// `[general]`, `[border]` and `[dwindle]`, and it catches the merely absurd (`0x1p10` is
    /// a gap of 1024 points) along with the non-finite.
    static func number(_ raw: TOMLValue?, _ path: String, in range: ClosedRange<Double>,
                       keeping current: Double, warnings: inout [String]) -> Double? {
        guard let value = raw?.doubleValue else { return nil }
        guard value.isFinite, range.contains(value) else {
            warnings.append("\(path): must be a number from \(brief(range.lowerBound)) to "
                            + "\(brief(range.upperBound)), using \(brief(current))")
            return nil
        }
        return value
    }

    /// `5` rather than `5.0`, so the warnings read the way the config file is written.
    private static func brief(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    public static func parse(_ text: String) throws -> Config {
        let root = try TOML.parse(text)
        var config = Config()

        if let general = root["general"]?.tableValue {
            if let s = general["super_key"]?.stringValue {
                switch s.lowercased() {
                case "alt", "opt", "option": config.superKey = .option
                case "cmd", "command": config.superKey = .command
                case "ctrl", "control": config.superKey = .control
                default: config.warnings.append("general.super_key: unknown value '\(s)', using alt")
                }
            }
            if let v = number(general["gaps_in"], "general.gaps_in", in: 0...500,
                              keeping: config.gaps.inner, warnings: &config.warnings) {
                config.gaps.inner = v
            }
            if let v = number(general["gaps_out"], "general.gaps_out", in: 0...500,
                              keeping: config.gaps.outer, warnings: &config.warnings) {
                config.gaps.outer = v
            }
        }

        if let d = root["dwindle"]?.tableValue {
            if let v = d["preserve_split"]?.boolValue { config.dwindle.preserveSplit = v }
            if let v = d["force_split"]?.intValue { config.dwindle.forceSplit = v }
            if let v = d["smart_split"]?.boolValue { config.dwindle.smartSplit = v }
            if let v = number(d["split_width_multiplier"], "dwindle.split_width_multiplier", in: 0.1...10,
                              keeping: config.dwindle.splitWidthMultiplier, warnings: &config.warnings) {
                config.dwindle.splitWidthMultiplier = v
            }
            // The same range the layout clamps to on use, so a value outside it is named here
            // rather than silently becoming a different one later.
            if let v = number(d["default_split_ratio"], "dwindle.default_split_ratio", in: 0.1...1.9,
                              keeping: config.dwindle.defaultSplitRatio, warnings: &config.warnings) {
                config.dwindle.defaultSplitRatio = v
            }
            if let v = d["split_bias"]?.intValue { config.dwindle.splitBias = v }
        }

        if let b = root["border"]?.tableValue {
            if let v = b["enabled"]?.boolValue { config.border.enabled = v }
            if let v = number(b["width"], "border.width", in: 0...100,
                              keeping: config.border.width, warnings: &config.warnings) {
                config.border.width = v
            }
            if let v = b["active_start"]?.stringValue { config.border.activeStart = v }
            if let v = b["active_end"]?.stringValue { config.border.activeEnd = v }
            if let v = number(b["angle"], "border.angle", in: 0...360,
                              keeping: config.border.angle, warnings: &config.warnings) {
                config.border.angle = v
            }
            // -1 is the documented "follow the window's own corner radius", and is the only
            // negative the range admits: every other one means the same thing, and accepting
            // them all would make a typo indistinguishable from a choice.
            if let v = number(b["radius"], "border.radius", in: -1...100,
                              keeping: config.border.radius, warnings: &config.warnings) {
                config.border.radius = v
            }
        }

        if let b = root["bar"]?.tableValue {
            if let v = b["persistent_workspaces"]?.intValue {
                let allowed = 0...WorkspaceManager.workspaceCount
                if allowed.contains(v) {
                    config.bar.persistentWorkspaces = v
                } else {
                    config.warnings.append("bar.persistent_workspaces: must be 0 ... \(WorkspaceManager.workspaceCount), using \(config.bar.persistentWorkspaces)")
                }
            }
        }

        if let f = root["floating"]?.tableValue {
            if let v = f["width"]?.doubleValue {
                if v > 0, v <= 1 { config.floating.width = v } else {
                    config.warnings.append("floating.width: must be over 0 and at most 1, using \(config.floating.width)")
                }
            }
            if let v = f["height"]?.doubleValue {
                if v > 0, v <= 1 { config.floating.height = v } else {
                    config.warnings.append("floating.height: must be over 0 and at most 1, using \(config.floating.height)")
                }
            }
            if let v = f["large_width"]?.doubleValue {
                if v > 0, v <= 1 { config.floating.largeWidth = v } else {
                    config.warnings.append("floating.large_width: must be over 0 and at most 1, using \(config.floating.largeWidth)")
                }
            }
            if let v = f["large_height"]?.doubleValue {
                if v > 0, v <= 1 { config.floating.largeHeight = v } else {
                    config.warnings.append("floating.large_height: must be over 0 and at most 1, using \(config.floating.largeHeight)")
                }
            }
            if let v = f["max_aspect_ratio"]?.doubleValue {
                if v > 0 { config.floating.maxAspectRatio = v } else {
                    config.warnings.append("floating.max_aspect_ratio: must be over 0, using \(config.floating.maxAspectRatio)")
                }
            }
        }

        if let g = root["gestures"]?.tableValue, let raw = g["swallow_dock_swipes"] {
            // Warned about rather than silently ignored: a mistyped boolean here quietly hands
            // Mission Control back the gesture that puts the off-screen stash on display.
            if let v = raw.boolValue {
                config.gestures.swallowDockSwipes = v
            } else {
                config.warnings.append("gestures.swallow_dock_swipes: must be true or false, using \(config.gestures.swallowDockSwipes)")
            }
        }

        if let m = root["misc"]?.tableValue {
            if let raw = m["disable_expose_shortcuts"] {
                if let v = raw.boolValue {
                    config.misc.disableExposeShortcuts = v
                } else {
                    config.warnings.append("misc.disable_expose_shortcuts: must be true or false, using \(config.misc.disableExposeShortcuts)")
                }
            }
            if let raw = m["disable_wallpaper_click"] {
                if let v = raw.boolValue {
                    config.misc.disableWallpaperClick = v
                } else {
                    config.warnings.append("misc.disable_wallpaper_click: must be true or false, using \(config.misc.disableWallpaperClick)")
                }
            }
            if let raw = m["prevent_hiding"] {
                if let v = raw.boolValue {
                    config.misc.preventHiding = v
                } else {
                    config.warnings.append("misc.prevent_hiding: must be true or false, using \(config.misc.preventHiding)")
                }
            }
            if let raw = m["restore_session"] {
                if let v = raw.boolValue {
                    config.misc.restoreSession = v
                } else {
                    config.warnings.append("misc.restore_session: must be true or false, using \(config.misc.restoreSession)")
                }
            }
        }

        if let binds = root["binds"]?.tableValue {
            // Sorted so the tooltip and any diagnostics are stable run to run.
            for spec in binds.keys.sorted() {
                guard let raw = binds[spec]?.stringValue else {
                    config.warnings.append("binds.\(spec): value must be a string")
                    continue
                }
                do {
                    let (mods, code, keyName) = try BindingParser.parse(spec, superKey: config.superKey)
                    let command = try CommandParser.parse(raw)
                    config.bindings.append(Binding(modifiers: mods, keyCode: code, keyName: keyName,
                                                   command: command, source: spec))
                } catch {
                    config.warnings.append("binds.\(spec): \(error)")
                }
            }
        }

        // Fill in any escape hatch the config did not bind. Only a command that is bound nowhere
        // gets one, so rebinding `quit` to something else keeps your key and does not also get
        // the default — the fallback is for the command being absent, not for the key being free.
        // A fallback whose own combination you have already used for something else is dropped
        // rather than registered twice: your binding wins, and the alternative is a duplicate the
        // system would refuse anyway.
        for fallback in Config.fallbackBindings
        where !config.bindings.contains(where: { $0.command == fallback.command }) {
            guard let (mods, code, keyName) = try? BindingParser.parse(fallback.spec,
                                                                       superKey: config.superKey),
                  !config.bindings.contains(where: { $0.modifiers == mods && $0.keyCode == code })
            else { continue }
            config.bindings.append(Binding(modifiers: mods, keyCode: code, keyName: keyName,
                                           command: fallback.command, source: fallback.spec))
        }

        if let floats = root["float"]?.arrayValue {
            var rules: [FloatRule] = []
            for entry in floats {
                guard let t = entry.tableValue else { continue }
                rules.append(FloatRule(app: t["app"]?.stringValue, title: t["title"]?.stringValue))
            }
            if !rules.isEmpty { config.floatRules = rules }
        }

        return config
    }
}
