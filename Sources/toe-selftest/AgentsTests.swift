import Foundation
import ToeCore

/// The agents widget (#203): Omarchy's `plugins/agents` cut to Claude Code. The fixtures are
/// upstream's own, from `test/shell.d/agent-usage-claude-limits-test.sh` at
/// omacom/omarchy@8b4eae66, re-expressed here.
func agentsTests(_ h: Harness) {

    func json(_ text: String) -> Data { Data(text.utf8) }
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    h.test("the usage answer reads every window once, on the payload's own scale") { t in
        // Upstream's first fixture: the flat session and weekly windows, and — dropped — a repeat
        // of a scoped window already read, a blank name, and a percent that will not parse.
        let limits = try ClaudeUsage.parse(json("""
        {
          "five_hour": { "utilization": 78.0 },
          "seven_day": { "utilization": 12.0 },
          "seven_day_opus": null,
          "limits": [
            { "kind": "session", "percent": 78, "scope": null },
            { "kind": "weekly_all", "percent": 12, "scope": null },
            { "kind": "weekly_scoped", "percent": 17, "resets_at": "2026-08-15T03:00:00+00:00",
              "scope": { "model": { "id": "claude-fable-5", "display_name": "Fable" }, "surface": null } },
            { "kind": "weekly_scoped", "percent": 99, "scope": { "model": { "display_name": "Fable" } } },
            { "kind": "five_hour_scoped", "percent": 95, "scope": { "model": { "display_name": "Fable" } } },
            { "kind": "weekly_scoped", "percent": 42, "scope": { "model": { "id": "claude-opus-5", "display_name": null } } },
            { "kind": "weekly_scoped", "percent": 5, "scope": { "model": { "display_name": "  " } } },
            { "kind": "weekly_scoped", "percent": "unknown", "scope": { "model": { "display_name": "Opus" } } }
          ]
        }
        """))
        t.equal(limits.map(\.label), ["Session (5-hour)", "Weekly (7-day)", "Fable Weekly", "Fable Session",
                                      "claude-opus-5 Weekly"], "upstream's five, in its order")
        t.equal(limits.map { Int(($0.fraction * 100).rounded()) }, [78, 12, 17, 95, 42], "percentages read as fractions")
        t.equal(limits[2].resetsAt, ClaudeUsage.iso8601("2026-08-15T03:00:00Z"), "the scoped window's reset")
        t.equal(limits[0].resetsAt, nil, "no reset time is no reset time, not now")

        // Upstream's second: a payload that speaks fractions says so, and the scoped entries
        // are read on the same scale rather than assuming percentages.
        let fractions = try ClaudeUsage.parse(json("""
        { "five_hour": { "utilization": 0.78 },
          "limits": [ { "kind": "session", "percent": 0.78, "scope": null },
                      { "kind": "weekly_scoped", "percent": 0.42, "scope": { "model": { "display_name": "Fable" } } } ] }
        """))
        t.equal(fractions.map(\.fraction), [0.78, 0.42], "fractions kept as fractions")

        // One payload, one convention: a 1.0 beside a 37 is 1%, not 100%.
        let scale = try ClaudeUsage.parse(json(#"{"five_hour":{"utilization":1.0},"seven_day":{"utilization":37}}"#))
        t.near(scale.first?.fraction, 0.01, "1.0 among percentages is one percent")
        let string = try ClaudeUsage.parse(json(#"{"five_hour":{"utilization":"45%"}}"#))
        t.near(string.first?.fraction, 0.45, "a percentage spelled as text")

        // seven_day_oauth_apps comes before seven_day, as upstream reads it.
        let oauth = try ClaudeUsage.parse(json(#"{"seven_day":{"utilization":10},"seven_day_oauth_apps":{"utilization":20}}"#))
        t.near(oauth.first?.fraction, 0.2, "the OAuth apps' weekly window wins")

        // Nothing to show is an error, not an empty panel with no reason on it.
        t.expect((try? ClaudeUsage.parse(json(#"{"five_hour":null}"#))) == nil, "no limits is refused")
        t.expect((try? ClaudeUsage.parse(json("<html>"))) == nil, "not JSON is refused")
    }

    h.test("resets_at in each of its three spellings") { t in
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        t.equal(ClaudeUsage.resetDate(1_790_000_000), when, "epoch seconds")
        t.equal(ClaudeUsage.resetDate(1_790_000_000_000.0), when, "epoch milliseconds")
        t.equal(ClaudeUsage.resetDate("1790000000"), when, "epoch seconds as text")
        t.equal(ClaudeUsage.resetDate("1790000000000"), when, "epoch milliseconds as text")
        let iso = ClaudeUsage.resetDate("2026-09-30T22:39:33Z")
        t.equal(iso, Date(timeIntervalSince1970: 1_790_807_973), "ISO in UTC")
        t.equal(ClaudeUsage.resetDate("2026-10-01T00:39:33+02:00"), iso, "an offset is honoured")
        t.equal(ClaudeUsage.resetDate("2026-09-30T22:39:33"), iso, "no offset is UTC, as upstream reads it")
        t.near(ClaudeUsage.resetDate("2026-09-30T22:39:33.250000+00:00")?.timeIntervalSince(iso!), 0.25,
               "Python's microseconds, which ISO8601DateFormatter will not read")
        t.equal(ClaudeUsage.resetDate("soon"), nil, "text that is not a time")
        t.equal(ClaudeUsage.resetDate(true), nil, "a boolean is not a time")
        t.equal(ClaudeUsage.resetDate(0), nil, "zero is not a time")
    }

    h.test("the saved sign-in yields a token, an expiry and a plan, and nothing else") { t in
        let saved = ClaudeUsage.credentials(json("""
        {"claudeAiOauth":{"accessToken":"sk-test","refreshToken":"rt-test","expiresAt":1790807973000,
          "rateLimitTier":"default_claude_max_20x","subscriptionType":"max"}}
        """))
        t.equal(saved?.accessToken, "sk-test", "the access token")
        t.equal(saved?.expiresAt, Date(timeIntervalSince1970: 1_790_807_973), "expiresAt is milliseconds")
        t.equal(saved?.plan, "Max 20x", "the tier names the plan")
        t.expect(saved?.isExpired(at: Date(timeIntervalSince1970: 1_790_807_974)) == true, "expired a second later")
        t.expect(saved?.isExpired(at: Date(timeIntervalSince1970: 1_790_807_900)) == false, "live a minute before")

        t.equal(ClaudeUsage.plan(tier: nil, subscription: "pro"), "Pro", "the subscription, capitalised")
        t.equal(ClaudeUsage.plan(tier: "default_claude_pro", subscription: nil), nil, "a tier with no max_ and no subscription")
        t.equal(ClaudeUsage.credentials(json(#"{"claudeAiOauth":{"accessToken":""}}"#)), nil, "an empty token is none")
        t.equal(ClaudeUsage.credentials(json(#"{"other":{}}"#)), nil, "no claudeAiOauth is none")
    }

    h.test("a request goes at most every 15 s, and never inside a 429's wait") { t in
        let now = Date(timeIntervalSince1970: 1_000_000)
        t.expect(ClaudeUsage.mayProbe(now: now, lastProbe: nil, force: false, blockedUntil: nil), "the first one goes")
        t.expect(!ClaudeUsage.mayProbe(now: now, lastProbe: now - 10, force: false, blockedUntil: nil),
                 "a panel opened 10 s after the last request does not ask again")
        t.expect(ClaudeUsage.mayProbe(now: now, lastProbe: now - 15, force: false, blockedUntil: nil), "15 s on it does")
        t.expect(ClaudeUsage.mayProbe(now: now, lastProbe: now - 1, force: true, blockedUntil: nil),
                 "Refresh is a person asking, and passes the floor")
        t.expect(!ClaudeUsage.mayProbe(now: now, lastProbe: nil, force: true, blockedUntil: now + 1),
                 "but not a 429: the server asked for quiet")
        t.expect(ClaudeUsage.mayProbe(now: now, lastProbe: nil, force: false, blockedUntil: now), "the wait has passed")

        t.equal(ClaudeUsage.problem(status: 429, retryAfter: 120, now: now), .rateLimited(until: now + 120), "retry-after")
        t.equal(ClaudeUsage.problem(status: 429, retryAfter: nil, now: now), .rateLimited(until: now + 60), "a default wait")
        t.equal(ClaudeUsage.problem(status: 401, retryAfter: nil, now: now), .signInExpired, "a refused token")
        t.equal(ClaudeUsage.problem(status: nil, retryAfter: nil, now: now), .unreachable, "no answer at all")
        t.equal(ClaudeUsage.problem(status: 500, retryAfter: nil, now: now), .failed("returned status 500"), "anything else")
    }

    h.test("cached limits are kept until their windows reset") { t in
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cache = ClaudeUsage.Cache(fetchedAt: now - 600, limits: [
            .init(label: "Session (5-hour)", fraction: 0.4, resetsAt: now - 1),
            .init(label: "Weekly (7-day)", fraction: 0.1, resetsAt: now + 3600),
            .init(label: "Fable Weekly", fraction: 0.2),
        ])
        t.equal(cache.openLimits(at: now).map(\.label), ["Weekly (7-day)", "Fable Weekly"],
                "a reset window's figure describes a period that is over; no reset time is kept")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(ClaudeUsage.Cache.self, from: encoder.encode(cache))
        t.equal(back, cache, "the cache survives a round trip through its file")
    }

    h.test("transcripts are counted once per message, by day and by model") { t in
        var scan = ClaudeTranscripts(calendar: utc)
        let a = #"{"type":"assistant","timestamp":"2026-09-29T10:00:00Z","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":1000,"cache_creation_input_tokens":5}}}"#
        let repeatOfA = a   // Claude Code writes one line per content block, each with the same usage
        let b = #"{"type":"assistant","timestamp":"2026-09-30T09:00:00.123Z","message":{"id":"msg_2","model":"claude-sonnet-5-5-20260101","usage":{"input_tokens":7,"output_tokens":3}}}"#
        let user = #"{"type":"user","message":{"role":"user","content":"hi, \"usage\": none"}}"#
        let partial = #"{"type":"assistant","message":{"id":"msg_3","usa"#
        let text = [a, repeatOfA, user, b].joined(separator: "\n") + "\n" + partial
        let used = scan.consume(Data(text.utf8), file: "/p/s.jsonl")
        t.equal(used, text.utf8.count - partial.utf8.count, "the half-written last line is left for next time")
        t.equal(scan.stats.byModel["claude-opus-5-5"]?.total, 1125, "the repeat is not counted twice")
        t.equal(scan.stats.byModel["claude-opus-5-5"]?.cacheRead, 1000, "cache reads count, as upstream counts them")
        t.equal(scan.stats.byDay, ["2026-09-29": 1125, "2026-09-30": 10], "by local day")

        // The rest of the partial line arrives, and the same message in another file (a resumed
        // session) does not count again.
        let rest = partial + #"ge":{"output_tokens":50}},"timestamp":"2026-09-30T11:00:00Z"}"# + "\n"
        _ = scan.consume(Data(rest.utf8), file: "/p/s.jsonl")
        _ = scan.consume(Data((b + "\n").utf8), file: "/p/resumed.jsonl")
        t.equal(scan.stats.byDay["2026-09-30"], 60, "the finished line is read; the copy is not")
        t.equal(scan.consume(Data("no newline".utf8), file: "/p/x.jsonl"), 0, "nothing whole, nothing taken")
    }

    h.test("the agents panel is Omarchy's, cut to Claude") { t in
        let now = ClaudeUsage.iso8601("2026-09-30T12:00:00Z")!
        let usage = AgentUsage(plan: "Max 20x", limits: [
            .init(label: "Session (5-hour)", fraction: 0.37, resetsAt: now + 2 * 3600 + 13 * 60),
            .init(label: "Weekly (7-day)", fraction: 0.92, resetsAt: now + 3 * 86400 + 4 * 3600),
        ], fetchedAt: now, tokens: TokenStats(
            byDay: ["2026-09-30": 1_234_567, "2026-09-28": 800, "2026-09-20": 99],
            byModel: ["claude-opus-5-5": .init(input: 5_000_000), "claude-haiku-4-5-20251001": .init(output: 3000),
                      "claude-sonnet-5-5": .init(input: 40_000), "claude-fable-5-1": .init(input: 900),
                      "<synthetic>": .init(input: 1)]))
        let rows = AgentsPanel.rows(usage, now: now, calendar: utc)
        t.equal(rows.first?.kind, .hero(glyph: Glyphs.agents, title: "Claude Code", status: "Max 20x",
                                        trailing: .text("92%")), "the plan, and the fullest window's number")
        t.equal(rows[1].kind, .header("Limits", trailing: nil), "then the limits")
        t.equal(rows[2].kind, .info([PanelRow.Info("Session (5-hour)", "37%")]), "a limit's label and share")
        t.equal(rows[3].kind, .progress(0.37), "its meter")
        t.equal(rows[4].kind, .note("Resets in 2h 13m"), "and when it resets")
        t.equal(rows[7].kind, .note("Resets in 3d 4h"), "days and hours past a day")

        let days = AgentsPanel.recentDays(usage.tokens!, now: now, calendar: utc)
        t.equal(days.map(\.label), ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Today"], "seven days, today last")
        t.equal(days.map(\.value), [0, 0, 0, 0, 800, 0, 1_234_567], "a quiet day is a zero; a week ago is out")
        t.expect(rows.contains(.header("Tokens by day", trailing: "1.2M")), "the week's total on the header")
        t.expect(rows.contains(.info([PanelRow.Info("Mon", "800"), PanelRow.Info("Tue", "0")])), "two days a row")
        t.equal(AgentsPanel.topModels(usage.tokens!).map(\.id),
                ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5-20251001", "claude-fable-5-1"],
                "the four biggest")
        t.expect(rows.contains(.info([PanelRow.Info("Opus 5.5", "5.0M"), PanelRow.Info("Sonnet 5.5", "40.0K")])),
                 "by model, with friendly names")

        t.equal(Array(rows.suffix(2).map(\.action)), [.refreshAgents, .openAgentUsage],
                "it ends on Refresh and claude.ai's usage page")
        t.equal(PanelState(rows: rows).rows.filter(\.isSelectable).count, 2, "and those are the only rows to land on")
    }

    h.test("the agents panel says why the limits are missing or stale") { t in
        let now = Date(timeIntervalSince1970: 1_000_000)
        let kept = AgentUsage(limits: [.init(label: "Weekly (7-day)", fraction: 0.5)], problem: .signInExpired)
        let rows = AgentsPanel.rows(kept, now: now)
        if case .hero(_, _, let status, _) = rows[0].kind { t.equal(status, "Sign-in expired", "the hero says so") }
        t.equal(rows[1].kind, .note("Claude Code's saved sign-in expired. Showing the last known limits. "
                                    + "Start Claude Code to refresh it."), "and the note says what to do")
        t.expect(rows.contains(.progress(0.5)), "the last known limits are still shown")

        let limited = AgentsPanel.rows(AgentUsage(problem: .rateLimited(until: now + 125)), now: now)
        t.equal(limited[1].kind, .note("Anthropic is rate limiting usage checks for 2m."), "how long the wait is")
        let first = AgentsPanel.rows(AgentUsage(), now: now)
        t.equal(first[1].kind, .note("Checking Claude's limits…"), "before the first answer")
    }

    h.test("formatting follows upstream's panel") { t in
        t.equal(AgentsPanel.duration(59), "1m", "never under a minute")
        t.equal(AgentsPanel.duration(0), "now", "a reset that is due")
        t.equal(AgentsPanel.duration(90 * 60), "1h 30m", "hours and minutes")
        t.equal(AgentsPanel.count(999), "999", "a small count as it is")
        t.equal(AgentsPanel.count(1_500), "1.5K", "thousands")
        t.equal(AgentsPanel.count(2_000_000_000), "2.0B", "billions")
        t.equal(AgentsPanel.modelName("claude-opus-4-8-20260101"), "Opus 4.8", "the prefix and date stamp go")
        t.equal(AgentsPanel.modelName("claude-3-5-sonnet"), "3.5 Sonnet", "a leading version")
        t.equal(AgentsPanel.modelName(""), "Unknown", "no id")
    }

    h.test("the agents widget is one glyph, urgent at 90%") { t in
        let metrics = BarMetrics()
        let calm = BarWidgets.agents(AgentUsage(limits: [.init(label: "Session (5-hour)", fraction: 0.89)]), metrics: metrics)
        t.equal(calm.text, Glyphs.agents, "the glyph whatever the numbers")
        t.expect(!calm.active, "89% is not an alarm")
        t.equal(calm.tooltip, "Claude: Session (5-hour) 89%", "the numbers are in the tooltip")
        let urgent = BarWidgets.agents(AgentUsage(limits: [.init(label: "Weekly (7-day)", fraction: 0.9)],
                                                  problem: .unreachable), metrics: metrics)
        t.expect(urgent.active, "90% is")
        t.equal(urgent.tooltip, "Claude: Weekly (7-day) 90% — offline", "a stale number says it may be")
        t.equal(Glyphs.agents.unicodeScalars.first?.value, 0xF16A3, "upstream's 󱚣")
        t.equal(PanelKind(widget: .agents), .agents, "a left click opens its panel")
    }

    h.test("[bar] agents is opt-in, and names what it cannot read") { t in
        t.equal(BarConfig().agents, [], "off by default: nothing is read")
        t.equal(BarConfig().agentsRefresh, 900, "upstream's interval")
        let on = try Config.parse("[bar]\nagents = [\"Claude\", \"claude\"]\nagents_refresh = 300\n")
        t.equal(on.bar.agents, ["claude"], "case-insensitive, once")
        t.equal(on.bar.agentsRefresh, 300, "the interval")
        let codex = try Config.parse("[bar]\nagents = [\"claude\", \"codex\"]\n")
        t.equal(codex.bar.agents, ["claude"], "codex is left out")
        t.expect(codex.warnings.contains { $0.contains("\"codex\"") }, "and named")
        let bare = try Config.parse("[bar]\nagents = \"claude\"\nagents_refresh = 5\n")
        t.equal(bare.bar.agents, [], "a bare string is not a list")
        t.equal(bare.warnings.count, 2, "both mistakes are named")
        t.equal(bare.bar.agentsRefresh, 900, "a minute at the least")
    }
}
