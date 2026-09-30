import Foundation

/// Reading what Anthropic and Claude Code say — the parsing half of
/// `bin/omarchy-agent-usage-claude` (MIT, © David Heinemeier Hansson, omacom/omarchy@8b4eae66),
/// in Swift and in the selftest.
///
/// The endpoint, `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta:
/// oauth-2025-04-20`, is undocumented and beta-flagged, which is why every rule here is
/// defensive: upstream has met percentages and fractions, `resets_at` as epoch seconds, epoch
/// milliseconds and ISO text, and model-scoped windows that appear only in a `limits` array while
/// the flat keys that once carried them sit at null. Anything that will not parse is left out
/// rather than guessed at.
public enum ClaudeUsage {

    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "oauth-2025-04-20"

    // MARK: - When to ask

    /// Upstream's `PROBE_MIN_INTERVAL_SECONDS`: a panel opened and shut repeatedly must not turn
    /// into a request per flick.
    public static let probeFloor: TimeInterval = 15
    /// How soon to try again after no answer at all — upstream's retry for the first probe
    /// after login, which often fires before the network has a route.
    public static let transportRetry: TimeInterval = 30
    /// How long a 429 with no `retry-after` keeps toe quiet.
    public static let defaultBackoff: TimeInterval = 60

    /// Whether a request may go now. A 429's wait binds even a forced refresh — the server
    /// asked, and pressing Refresh does not change its mind — while the floor is only for the
    /// panel's opens: a person who pressed Refresh wants numbers, which is upstream's `--force`.
    public static func mayProbe(now: Date, lastProbe: Date?, force: Bool, blockedUntil: Date?) -> Bool {
        if let blockedUntil, now < blockedUntil { return false }
        if force { return true }
        guard let lastProbe else { return true }
        return now.timeIntervalSince(lastProbe) >= probeFloor
    }

    /// What a refused answer means for the panel. A 401 is a token Anthropic no longer takes —
    /// revoked, or expired sooner than its `expiresAt` said — and only Claude Code can mend it.
    public static func problem(status: Int?, retryAfter: TimeInterval?, now: Date) -> AgentUsage.Problem {
        switch status {
        case nil:  return .unreachable
        case 401:  return .signInExpired
        case 429:  return .rateLimited(until: now + (retryAfter ?? defaultBackoff))
        case let code?: return .failed("returned status \(code)")
        }
    }

    // MARK: - The last good answer

    /// `~/.local/state/toe/agents-claude.json`: what the last successful request said, kept
    /// until each window resets — upstream's `claude-limits.json`, so a restart, an expired
    /// sign-in or a network outage still shows the numbers that are still true.
    public struct Cache: Equatable, Codable, Sendable {
        public var fetchedAt: Date
        public var limits: [AgentUsage.Limit]

        public init(fetchedAt: Date, limits: [AgentUsage.Limit]) {
            self.fetchedAt = fetchedAt
            self.limits = limits
        }

        /// The windows that have not reset since.
        public func openLimits(at now: Date) -> [AgentUsage.Limit] {
            limits.filter { $0.isOpen(at: now) }
        }
    }

    // MARK: - The saved sign-in

    /// What toe takes from Claude Code's saved credential, and all it takes: the access token
    /// for one header, its expiry so an expired one is never sent, and the plan's name. The
    /// refresh token is not read into this at all.
    public struct Credentials: Equatable, Sendable {
        public var accessToken: String
        public var expiresAt: Date?
        public var plan: String?

        public init(accessToken: String, expiresAt: Date? = nil, plan: String? = nil) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
            self.plan = plan
        }

        public func isExpired(at now: Date) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }
    }

    /// The Keychain item's JSON (`{"claudeAiOauth": {...}}`, the same document
    /// `~/.claude/.credentials.json` holds where there is no Keychain). Nil when there is no
    /// usable token in it.
    public static func credentials(_ data: Data) -> Credentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["claudeAiOauth"] as? [String: Any],
              let token = login["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let expires = number(login["expiresAt"]).flatMap { $0 > 0 ? epoch($0) : nil }
        return Credentials(accessToken: token, expiresAt: expires,
                           plan: plan(tier: login["rateLimitTier"] as? String,
                                      subscription: login["subscriptionType"] as? String))
    }

    /// Upstream's `plan_label`: `default_claude_max_20x` is "Max 20x"; otherwise the
    /// subscription type with a capital, "pro" → "Pro".
    public static func plan(tier: String?, subscription: String?) -> String? {
        if let tier, let range = tier.range(of: #"max_(\d+x)"#, options: [.regularExpression, .caseInsensitive]) {
            return "Max " + tier[range].dropFirst(4).lowercased()
        }
        guard let subscription, let first = subscription.first else { return nil }
        return first.uppercased() + subscription.dropFirst()
    }

    // MARK: - The usage answer

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case notJSON
        case noLimits
        public var description: String {
            switch self {
            case .notJSON:  return "returned something that is not JSON"
            case .noLimits: return "returned no limits"
            }
        }
    }

    /// Upstream's `probe_limits` after the request: the session window, the weekly one
    /// (`seven_day_oauth_apps` before `seven_day`), then every model-scoped window in `limits`
    /// once each, in the order the payload lists them.
    public static func parse(_ data: Data) throws -> [AgentUsage.Limit] {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notJSON
        }
        let weekly = payload["seven_day_oauth_apps"] as? [String: Any] ?? payload["seven_day"] as? [String: Any]
        let session = payload["five_hour"] as? [String: Any]
        let entries = (payload["limits"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []

        // One payload speaks one convention, so the scale is settled across all of it: any value
        // of 1 or more means percentages, and then 1.0 is 1%, not 100%.
        let raw = [session?["utilization"], weekly?["utilization"]] + entries.map { $0["percent"] }
        let percentScale = raw.contains { utilization($0).map { $0 >= 1 } ?? false }

        var limits: [AgentUsage.Limit] = []
        if let session, let fraction = normalized(session["utilization"], percentScale: percentScale) {
            limits.append(.init(label: "Session (5-hour)", fraction: fraction, resetsAt: resetDate(session["resets_at"])))
        }
        if let weekly, let fraction = normalized(weekly["utilization"], percentScale: percentScale) {
            limits.append(.init(label: "Weekly (7-day)", fraction: fraction, resetsAt: resetDate(weekly["resets_at"])))
        }
        // A model can hold more than one scoped window, and only the pair of model and window
        // tells them apart — so both make the title and both make the key that keeps a repeat
        // out. Entries with no model are the flat windows again, already read above.
        var seen = Set<String>()
        for entry in entries {
            guard let model = (entry["scope"] as? [String: Any])?["model"] as? [String: Any] else { continue }
            let name = ((model["display_name"] as? String) ?? (model["id"] as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            let kind = ((entry["kind"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !seen.contains(name + "\u{0}" + kind),
                  let fraction = normalized(entry["percent"], percentScale: percentScale)
            else { continue }
            seen.insert(name + "\u{0}" + kind)
            let window = scopedWindow(kind)
            limits.append(.init(label: window.isEmpty ? name : "\(name) \(window)",
                                fraction: fraction, resetsAt: resetDate(entry["resets_at"])))
        }
        guard !limits.isEmpty else { throw ParseError.noLimits }
        return limits
    }

    /// Upstream's `scoped_window`: the window read out of `kind` here rather than out of a title
    /// later, since a model called "Opus 5 (1M context)" would read as a one-minute window.
    static func scopedWindow(_ kind: String) -> String {
        let text = kind.lowercased()
        if text.contains("month") { return "Monthly" }
        if text.contains("week") || text.contains("day") { return "Weekly" }
        if text.contains("hour") || text.contains("session") { return "Session" }
        return ""
    }

    /// A number, or a string of one with an optional `%`; nil for anything else.
    static func utilization(_ value: Any?) -> Double? {
        if let n = plainNumber(value) { return n.isNaN ? nil : n }
        if let s = value as? String {
            return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
        }
        return nil
    }

    static func normalized(_ value: Any?, percentScale: Bool) -> Double? {
        guard let n = utilization(value), n >= 0 else { return nil }
        return min(1, percentScale || n > 1 ? n / 100 : n)
    }

    /// `resets_at` in any of its three spellings: epoch seconds, epoch milliseconds (anything
    /// past 10¹², which as seconds is the year 33658), or ISO 8601 with or without a fraction
    /// and an offset — Python's `isoformat` writes microseconds, which `ISO8601DateFormatter`
    /// will not read, so the text is taken apart by hand. No offset is UTC, as upstream reads it.
    public static func resetDate(_ value: Any?) -> Date? {
        if let n = plainNumber(value) { return n > 0 ? epoch(n) : nil }
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.allSatisfy(\.isNumber), let n = Double(raw) { return n > 0 ? epoch(n) : nil }
        return iso8601(raw)
    }

    static func epoch(_ n: Double) -> Date {
        Date(timeIntervalSince1970: n >= 1e12 ? n / 1000 : n)
    }

    static func number(_ value: Any?) -> Double? {
        if let n = plainNumber(value) { return n }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// A JSON number that is not a JSON boolean. `value is Bool` cannot tell them apart —
    /// Foundation bridges every `NSNumber` holding 0 or 1 to `Bool`, so it would throw away a
    /// window at exactly 1% — and the CoreFoundation type is the only thing that can.
    static func plainNumber(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    private static let isoPattern = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$"#)

    public static func iso8601(_ text: String) -> Date? {
        let ns = text as NSString
        guard let m = isoPattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var parts = DateComponents()
        parts.year = Int(group(1)!); parts.month = Int(group(2)!); parts.day = Int(group(3)!)
        parts.hour = Int(group(4)!); parts.minute = Int(group(5)!); parts.second = Int(group(6)!)
        guard var date = utc.date(from: parts) else { return nil }
        if let fraction = group(7), let f = Double("0" + fraction) { date += f }
        if let zone = group(8), zone != "Z" {
            let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
            guard let hh = Int(digits.prefix(2)), let mm = Int(digits.suffix(2)) else { return nil }
            let offset = TimeInterval(hh * 3600 + mm * 60)
            date -= zone.hasPrefix("-") ? -offset : offset
        }
        return date
    }
}
