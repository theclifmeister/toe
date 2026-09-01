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
    public var bindings: [Binding] = []
    public var floatRules: [FloatRule] = Config.defaultFloatRules
    /// Non-fatal problems (a binding that would not parse, an unknown key). Surfaced in the
    /// menu bar item rather than thrown, so one typo never leaves you without a keyboard.
    public var warnings: [String] = []

    public init() {}

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
