import Foundation

/// Tokens counted from Claude Code's own transcripts — `~/.claude/projects/**/*.jsonl` — the way
/// upstream's `scan_projects` counts them (MIT, © David Heinemeier Hansson,
/// omacom/omarchy@8b4eae66 `bin/omarchy-agent-usage-claude`).
///
/// The difference is incremental: upstream rescans every file on every run and caches the
/// answer for fifteen minutes. On this machine that directory is over 600 MB, so the reader in
/// `toe` keeps a byte offset per file and hands this only what was appended since — whole lines
/// only, through `consume`, so a line Claude Code is halfway through writing is read next time
/// rather than half-read now.
public struct ClaudeTranscripts: Equatable, Sendable {

    public private(set) var stats = TokenStats()
    /// Every message already counted. Claude Code writes an assistant message once per content
    /// block, each copy carrying the same `usage`, and a resumed session repeats earlier
    /// messages into its new file — so the key is the message id across every file, not the
    /// line. Kept in memory for the life of the process, which is also how long the offsets are.
    private var seen = Set<String>()
    private let calendar: Calendar

    /// `calendar` decides which local day a timestamp falls on; the selftest pins its zone.
    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Takes the whole lines at the front of `chunk` and answers how many bytes they were, so the
    /// caller can advance its offset by exactly that. A trailing partial line is left for the
    /// next read. `file` stands in for a message id on the rare line that has none.
    public mutating func consume(_ chunk: Data, file: String) -> Int {
        guard let lastNewline = chunk.lastIndex(of: 0x0A) else { return 0 }
        let whole = chunk[chunk.startIndex...lastNewline]
        var lineNumber = 0
        for line in whole.split(separator: 0x0A, omittingEmptySubsequences: false) {
            lineNumber += 1
            add(line: Data(line), fallbackKey: "\(file):\(lineNumber)")
        }
        return whole.count
    }

    /// One transcript line. Anything that is not an assistant message with a positive `usage`
    /// is passed over.
    public mutating func add(line: Data, fallbackKey: String) {
        // Upstream's cheap pre-filter: most lines are tool output and user turns, and parsing
        // JSON is the expensive part.
        guard line.range(of: Self.usageMarker) != nil,
              let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }
        let message = entry["message"] as? [String: Any] ?? [:]
        guard entry["type"] as? String == "assistant" || message["role"] as? String == "assistant",
              let usage = (message["usage"] ?? entry["usage"]) as? [String: Any]
        else { return }

        let id = (message["id"] as? String) ?? (entry["messageId"] as? String) ?? ""
        let key = id.isEmpty ? (entry["uuid"] as? String).map { "uuid:\($0)" } ?? fallbackKey : id
        guard !seen.contains(key) else { return }

        func count(_ snake: String, _ camel: String) -> Int {
            max(0, Int((ClaudeUsage.number(usage[snake] ?? usage[camel]) ?? 0).rounded()))
        }
        let tokens = TokenStats.Tokens(input: count("input_tokens", "inputTokens"),
                                       output: count("output_tokens", "outputTokens"),
                                       cacheRead: count("cache_read_input_tokens", "cacheReadInputTokens"),
                                       cacheWrite: count("cache_creation_input_tokens", "cacheCreationInputTokens"))
        guard tokens.total > 0 else { return }
        seen.insert(key)

        let model = (message["model"] as? String) ?? (entry["model"] as? String) ?? "claude"
        // `<synthetic>` is what Claude Code writes for a message it made up itself — an API
        // error shown as a reply — and it carries zeros, which the guard above already drops.
        stats.byModel[model, default: .init()] = stats.byModel[model, default: .init()] + tokens
        if let day = day(of: entry["timestamp"] ?? message["timestamp"]) {
            stats.byDay[day, default: 0] += tokens.total
        }
    }

    private static let usageMarker = Data("\"usage\":".utf8)

    /// The local calendar day a timestamp falls on, `yyyy-MM-dd`. Nil when there is no
    /// timestamp — upstream files those under today, which would put last year's tokens on
    /// today's bar; toe counts them in the model totals and leaves the days alone.
    func day(of value: Any?) -> String? {
        guard let date = ClaudeUsage.resetDate(value) else { return nil }
        return Self.dayKey(date, calendar: calendar)
    }

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
