import Foundation

/// What the agents widget knows about one coding agent's subscription — Omarchy's per-agent
/// record (`~/.local/state/omarchy/agents/usage/<id>.json`), as a Swift value.
///
/// Ported from Omarchy's `omarchy.agents` plugin, MIT, © David Heinemeier Hansson:
/// `bin/omarchy-agent-usage-claude` and `shell/plugins/agents/` at omacom/omarchy@8b4eae66.
/// toe reads Claude Code only; the record keeps upstream's shape so a second agent would be a
/// second reader, not a second record.
public struct AgentUsage: Equatable, Sendable {

    /// One rate-limit window: "Session (5-hour)" at 37%, resetting at 14:00.
    public struct Limit: Equatable, Sendable, Codable {
        public var label: String
        /// 0…1 — upstream's `percent`, which is a fraction despite its name.
        public var fraction: Double
        /// Nil when the endpoint did not say, which it does not for every window.
        public var resetsAt: Date?

        public init(label: String, fraction: Double, resetsAt: Date? = nil) {
            self.label = label
            self.fraction = max(0, min(1, fraction))
            self.resetsAt = resetsAt
        }

        /// Upstream's `limit_window_open`: once a window has reset the figure describes a period
        /// that is over, and a cached 78% would misreport an allowance that is now untouched. A
        /// window with no reset time is kept — no timestamp is no reason to throw a number away.
        public func isOpen(at now: Date) -> Bool {
            guard let resetsAt else { return true }
            return resetsAt > now
        }
    }

    /// Why the limits are missing or may be stale. The limits that *are* there are still shown
    /// under any of these — the last good ones, kept until their windows reset.
    public enum Problem: Equatable, Sendable {
        /// No Claude Code sign-in in the Keychain at all.
        case notSignedIn
        /// The saved access token has lapsed. Only Claude Code may mint a new one — toe
        /// refreshing it would rotate the refresh token Claude Code depends on — so this waits
        /// for the next time Claude Code runs.
        case signInExpired
        /// HTTP 429, with the time `retry-after` said to wait until, when it said.
        case rateLimited(until: Date?)
        /// No answer at all: no route, no DNS, a timeout.
        case unreachable
        /// An answer toe could not use: another status, or a body with no limits in it.
        case failed(String)

        /// The hero's status line — upstream's `usageStatusText`.
        public var headline: String {
            switch self {
            case .notSignedIn:   return "Not signed in"
            case .signInExpired: return "Sign-in expired"
            case .rateLimited:   return "Rate limited"
            case .unreachable:   return "Offline"
            case .failed:        return "Limits unavailable"
            }
        }

        /// The note under the hero — upstream's `authHelpText`, in the panel's register.
        public func detail(hasLimits: Bool, now: Date) -> String {
            let kept = hasLimits ? " Showing the last known limits." : ""
            switch self {
            case .notSignedIn:
                return "Claude Code has no saved sign-in. Run `claude` and sign in."
            case .signInExpired:
                return "Claude Code's saved sign-in expired.\(kept) Start Claude Code to refresh it."
            case .rateLimited(let until):
                let wait = until.map { $0 > now ? " for \(AgentsPanel.duration($0.timeIntervalSince(now)))" : "" } ?? ""
                return "Anthropic is rate limiting usage checks\(wait).\(kept)"
            case .unreachable:
                return "Couldn't reach Anthropic's usage endpoint.\(kept)"
            case .failed(let why):
                return "Anthropic's usage endpoint \(why).\(kept)"
            }
        }
    }

    /// `rateLimitTier` / `subscriptionType` as a plan name — "Max 20x", "Pro" — or nil.
    public var plan: String?
    public var limits: [Limit]
    public var problem: Problem?
    /// When the limits were last fetched, not when the record was built.
    public var fetchedAt: Date?
    /// Counted from Claude Code's own transcripts; nil until the first scan has finished.
    public var tokens: TokenStats?

    public init(plan: String? = nil, limits: [Limit] = [], problem: Problem? = nil,
                fetchedAt: Date? = nil, tokens: TokenStats? = nil) {
        self.plan = plan
        self.limits = limits
        self.problem = problem
        self.fetchedAt = fetchedAt
        self.tokens = tokens
    }

    /// The fullest window — the one that will stop you first, and the hero's number.
    public var binding: Limit? { limits.max(by: { $0.fraction < $1.fraction }) }

    /// Upstream's alarm: any window at 90% or more.
    public static let alarmThreshold = 0.9
    public var alarming: Bool { limits.contains { $0.fraction >= Self.alarmThreshold } }
}

/// Tokens by day and by model, the two sections at the bottom of Omarchy's panel.
public struct TokenStats: Equatable, Sendable {
    /// One model's four counters, as the transcripts' `usage` spells them.
    public struct Tokens: Equatable, Sendable {
        public var input = 0
        public var output = 0
        public var cacheRead = 0
        public var cacheWrite = 0
        public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
        }
        /// Upstream counts all four, cache included: it is what the subscription is spending.
        public var total: Int { input + output + cacheRead + cacheWrite }

        static func + (a: Tokens, b: Tokens) -> Tokens {
            Tokens(input: a.input + b.input, output: a.output + b.output,
                   cacheRead: a.cacheRead + b.cacheRead, cacheWrite: a.cacheWrite + b.cacheWrite)
        }
    }

    /// Total tokens per local calendar day, keyed `yyyy-MM-dd`.
    public var byDay: [String: Int]
    /// All-time, per model id as the transcript wrote it (`claude-opus-5-5`).
    public var byModel: [String: Tokens]

    public init(byDay: [String: Int] = [:], byModel: [String: Tokens] = [:]) {
        self.byDay = byDay
        self.byModel = byModel
    }
}
