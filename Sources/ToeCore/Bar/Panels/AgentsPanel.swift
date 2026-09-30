import Foundation

/// The agents panel — `shell/plugins/agents/Panel.qml` on Omarchy's `quattro` branch (MIT,
/// © David Heinemeier Hansson, omacom/omarchy@8b4eae66), cut to Claude Code.
///
/// Upstream is a hero with the plan, a LIMITS section of meters with "Resets in …", a BALANCE
/// for prepaid agents, TOKENS BY DAY as seven bars and TOKENS BY MODEL as the top four. What is
/// gone: the vendor chips (one vendor), the balance (Fireworks only), and the bars — the week
/// is seven `InfoPair` cells here, the numbers the bars' tooltips carry upstream, because a row
/// type for a bar chart is a second drawing path for one panel. The meters are the power panel's
/// progress row. What is added is the panel's last row: where the Settings door stands on every
/// other panel stands claude.ai's own usage page, the Mac-side "more about this".
public enum AgentsPanel {

    public static func rows(_ usage: AgentUsage, now: Date, calendar: Calendar = .current) -> [PanelRow] {
        let status = usage.problem?.headline ?? usage.plan ?? "Subscription"
        let trailing = usage.binding.map { PanelRow.HeroTrailing.text(percent($0.fraction)) }
        var rows: [PanelRow] = [.hero(glyph: Glyphs.agents, title: "Claude Code", status: status, trailing: trailing)]

        if let problem = usage.problem {
            rows.append(.note(problem.detail(hasLimits: !usage.limits.isEmpty, now: now)))
        }

        if !usage.limits.isEmpty {
            rows.append(.header("Limits"))
            for limit in usage.limits {
                rows.append(.info([PanelRow.Info(limit.label, percent(limit.fraction))]))
                rows.append(.progress(limit.fraction))
                if let resetsAt = limit.resetsAt, resetsAt > now {
                    rows.append(.note("Resets in \(duration(resetsAt.timeIntervalSince(now)))"))
                }
            }
        } else if usage.problem == nil {
            rows.append(.note(usage.fetchedAt == nil ? "Checking Claude's limits…" : "No limits reported."))
        }

        if let tokens = usage.tokens {
            let days = recentDays(tokens, now: now, calendar: calendar)
            rows.append(.header("Tokens by day", trailing: count(days.reduce(0) { $0 + $1.value })))
            rows += pairs(days.map { PanelRow.Info($0.label, count($0.value)) })
            let models = topModels(tokens)
            if !models.isEmpty {
                rows.append(.header("Tokens by model"))
                rows += pairs(models.map { PanelRow.Info(modelName($0.id), count($0.tokens.total)) })
            }
        }

        rows += [.separator, .action("Refresh", .refreshAgents), .action("Open usage on claude.ai…", .openAgentUsage)]
        return rows
    }

    /// Upstream's week: the last seven local days, oldest first, today last and called "Today";
    /// a day with nothing on it is a zero, not a gap.
    public static func recentDays(_ tokens: TokenStats, now: Date,
                                  calendar: Calendar) -> [(label: String, value: Int)] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return (0..<7).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { return nil }
            let key = ClaudeTranscripts.dayKey(date, calendar: calendar)
            return (back == 0 ? "Today" : formatter.string(from: date), tokens.byDay[key] ?? 0)
        }
    }

    /// Upstream's `modelRows`: the four biggest, all-time.
    public static func topModels(_ tokens: TokenStats) -> [(id: String, tokens: TokenStats.Tokens)] {
        tokens.byModel
            .map { (id: $0.key, tokens: $0.value) }
            .sorted { $0.tokens.total != $1.tokens.total ? $0.tokens.total > $1.tokens.total : $0.id < $1.id }
            .prefix(4)
            .map { $0 }
    }

    /// Two `InfoPair` cells a row, as the power panel lays its stats out.
    static func pairs(_ cells: [PanelRow.Info]) -> [PanelRow] {
        stride(from: 0, to: cells.count, by: 2).map { .info(Array(cells[$0..<min($0 + 2, cells.count)])) }
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }

    /// Upstream's `formatDuration`: "2d 3h", "4h 12m", "7m", never under a minute.
    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "now" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(max(1, minutes))m"
    }

    /// Upstream's `formatTokenCount`: 1.2B, 3.4M, 5.6K, or the number.
    public static func count(_ n: Int) -> String {
        let value = Double(n)
        if value >= 1e9 { return String(format: "%.1fB", value / 1e9) }
        if value >= 1e6 { return String(format: "%.1fM", value / 1e6) }
        if value >= 1e3 { return String(format: "%.1fK", value / 1e3) }
        return String(n)
    }

    /// Upstream's `friendlyModelName`: `claude-opus-4-8-20260101` is "Opus 4.8" — the prefix and
    /// the date stamp dropped, the numeric run rejoined into one version, the words title-cased.
    public static func modelName(_ id: String) -> String {
        var name = id.hasPrefix("claude-") ? String(id.dropFirst(7)) : id
        if let stamp = name.range(of: #"-\d{8}$"#, options: .regularExpression) { name.removeSubrange(stamp) }
        var words: [String] = []
        var version: [String] = []
        for part in name.split(separator: "-").map(String.init) where !part.isEmpty {
            if part.first?.isNumber == true {
                version.append(part)
                continue
            }
            if !version.isEmpty {
                words.append(version.joined(separator: "."))
                version = []
            }
            words.append(part.prefix(1).uppercased() + part.dropFirst())
        }
        if !version.isEmpty { words.append(version.joined(separator: ".")) }
        return words.isEmpty ? "Unknown" : words.joined(separator: " ")
    }
}
