import Foundation

public struct BorderConfig: Equatable {
    public var enabled: Bool = true
    public var width: Double = 2
    /// Omarchy's `col.active_border` gradient.
    public var activeStart: String = "#33ccffee"
    public var activeEnd: String = "#00ff99ee"
    public var angle: Double = 45
    /// Negative follows the system window corner radius, 0 is square, positive is an
    /// explicit value in points.
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
    /// Fraction of the monitor's usable width and height.
    public var width: Double = 0.70
    public var height: Double = 0.80
    /// Widest the window may be relative to its own height. On an ultrawide, 70% of the
    /// width is a letterbox; capping the ratio keeps a floating window a shape you would
    /// have picked by hand, on any display.
    public var maxAspectRatio: Double = 1.6
    public init() {}
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
            if let v = general["gaps_in"]?.doubleValue { config.gaps.inner = v }
            if let v = general["gaps_out"]?.doubleValue { config.gaps.outer = v }
        }

        if let d = root["dwindle"]?.tableValue {
            if let v = d["preserve_split"]?.boolValue { config.dwindle.preserveSplit = v }
            if let v = d["force_split"]?.intValue { config.dwindle.forceSplit = v }
            if let v = d["smart_split"]?.boolValue { config.dwindle.smartSplit = v }
            if let v = d["split_width_multiplier"]?.doubleValue { config.dwindle.splitWidthMultiplier = v }
            if let v = d["default_split_ratio"]?.doubleValue { config.dwindle.defaultSplitRatio = v }
            if let v = d["split_bias"]?.intValue { config.dwindle.splitBias = v }
        }

        if let b = root["border"]?.tableValue {
            if let v = b["enabled"]?.boolValue { config.border.enabled = v }
            if let v = b["width"]?.doubleValue { config.border.width = v }
            if let v = b["active_start"]?.stringValue { config.border.activeStart = v }
            if let v = b["active_end"]?.stringValue { config.border.activeEnd = v }
            if let v = b["angle"]?.doubleValue { config.border.angle = v }
            if let v = b["radius"]?.doubleValue { config.border.radius = v }
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
