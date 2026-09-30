import Foundation
import ToeCore

/// Claude Code's rate limits and token counts, for the agents widget — Omarchy's
/// `plugins/agents` with `bin/omarchy-agent-usage-claude` behind it (MIT, © David Heinemeier
/// Hansson, omacom/omarchy@8b4eae66), in Swift and cut to Claude.
///
/// **This is the bar's one always-on poll, and #171 says there should be none.** The rule is a
/// listener where one exists, and here none does: the limits are a number on Anthropic's
/// servers that moves as Claude Code is used, from this machine or any other, and nothing
/// tells a third party it moved. So it is asked every `[bar] agents_refresh` seconds — 900,
/// upstream's figure — and on a panel open no more than once every 15 s. What keeps that
/// honest: it runs only while `[bar] agents` lists `"claude"`, which is off by default; a 429's
/// `retry-after` stops it, forced refresh included; a sign-in that has expired stops it until
/// Claude Code runs again, rather than sending a token that will be refused; and the timer has
/// a tenth of its interval as tolerance so it can ride on some other wake-up.
///
/// **The token.** Claude Code keeps its OAuth sign-in in the login Keychain, generic password
/// `Claude Code-credentials`. toe reads it through `/usr/bin/security` rather than
/// `SecItemCopyMatching`: the item's access list names the tools that may read it without
/// asking, `security` is one of them, and toe is not — so the framework call would put up
/// "toe wants to use your confidential information" and the tool does not. Measured for
/// #203 from inside the app, before and after Claude Code refreshed the token: no prompt
/// either time. The token is read on every request, used for one header, and never kept,
/// logged or written; the refresh token beside it is never looked at. toe never refreshes the
/// sign-in itself — that would rotate the refresh token Claude Code depends on and sign it out.
///
/// **Tokens by day and by model** come from Claude Code's transcripts,
/// `~/.claude/projects/**/*.jsonl` — hundreds of megabytes on a machine that uses it, so the
/// scan keeps a byte offset per file and reads only what was appended since, off the main
/// thread. The offsets live as long as the process; the first scan after a launch reads it all.
///
/// Everything that blocks — `security`, the request, the files — runs on `queue` or in
/// `URLSession`; `onChange` and every property here are the main thread's.
final class AgentUsageProvider: BarProvider {

    /// nil while the widget is off.
    private(set) var usage: AgentUsage?
    var onChange: (() -> Void)?

    private var interval: TimeInterval = 900
    private var timer: Timer?
    private var retry: Timer?
    private var probing = false
    private var lastProbe: Date?
    /// Until when a 429 asked for quiet.
    private var blockedUntil: Date?

    private let queue = DispatchQueue(label: "com.clifmeister.toe.agents", qos: .utility)
    /// The queue's alone.
    private var transcripts = ClaudeTranscripts()
    private var offsets: [String: UInt64] = [:]
    private var scanning = false

    static let cacheURL = StateDirectory.url.appendingPathComponent("agents-claude.json")
    static let projectsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    /// The usage answer is a few hundred bytes; 256 KB is a ceiling nothing honest meets.
    private static let sizeLimit = 256 << 10

    // MARK: - BarProvider

    func start() {
        guard timer == nil else { return }
        if usage == nil {
            let cached = Self.loadCache()
            usage = AgentUsage(limits: cached?.openLimits(at: Date()) ?? [], fetchedAt: cached?.fetchedAt)
        }
        arm()
        refresh(force: false)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        retry?.invalidate()
        retry = nil
        usage = nil
    }

    /// A new `[bar] agents_refresh`, re-arming the timer if it is running.
    func setInterval(_ seconds: TimeInterval) {
        guard seconds != interval else { return }
        interval = seconds
        if timer != nil { arm() }
    }

    private func arm() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh(force: false) }
        timer.tolerance = interval / 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Refreshing

    /// Asks Anthropic for the limits and rescans the transcripts. `force` is a person asking —
    /// the Refresh row, a right click — and passes the 15-second floor; nothing passes a 429.
    func refresh(force: Bool) {
        guard usage != nil else { return }
        scan()
        let now = Date()
        guard !probing, ClaudeUsage.mayProbe(now: now, lastProbe: lastProbe, force: force, blockedUntil: blockedUntil)
        else { return }
        probing = true
        queue.async { [weak self] in
            let credentials = Self.readCredentials()
            DispatchQueue.main.async { self?.probe(with: credentials) }
        }
    }

    private func probe(with credentials: ClaudeUsage.Credentials?) {
        let now = Date()
        guard let credentials else {
            Log.info("agents: no Claude Code sign-in found")
            return finish(problem: .notSignedIn, plan: nil)
        }
        guard !credentials.isExpired(at: now) else {
            // Upstream's rule: an expired token is not sent. Claude Code refreshes it the next
            // time it runs, and the next tick after that finds a live one.
            return finish(problem: .signInExpired, plan: credentials.plan)
        }
        lastProbe = now
        var request = URLRequest(url: ClaudeUsage.endpoint)
        request.timeoutInterval = 10
        let task = BoundedGET.task(request, limit: Self.sizeLimit, allowedHosts: ["api.anthropic.com"],
                                   headers: ["Authorization": "Bearer \(credentials.accessToken)",
                                             "anthropic-beta": ClaudeUsage.betaHeader,
                                             "Accept": "application/json"]) { result in
            DispatchQueue.main.async { [weak self] in self?.answered(result, plan: credentials.plan) }
        }
        task.resume()
    }

    private func answered(_ result: Result<Data, BoundedGET.Failure>, plan: String?) {
        let now = Date()
        switch result {
        case .success(let data):
            do {
                let limits = try ClaudeUsage.parse(data)
                blockedUntil = nil
                Self.saveCache(ClaudeUsage.Cache(fetchedAt: now, limits: limits))
                Log.info("agents: \(limits.count) limit(s) from Anthropic")
                finish(problem: nil, plan: plan, limits: limits, fetchedAt: now)
            } catch let error as ClaudeUsage.ParseError {
                Log.error("agents: Anthropic's usage endpoint \(error)")
                finish(problem: .failed(error.description), plan: plan)
            } catch {
                finish(problem: .failed("returned something unexpected"), plan: plan)
            }
        case .failure(let failure):
            let problem = ClaudeUsage.problem(status: failure.status, retryAfter: failure.retryAfter, now: now)
            Log.error("agents: usage request failed: \(failure)")
            switch problem {
            case .rateLimited(let until): blockedUntil = until
            case .unreachable: retryAfterTransportFailure()
            default: break
            }
            finish(problem: problem, plan: plan)
        }
    }

    /// Settles a round: new limits if there are any, otherwise the ones still open from before.
    private func finish(problem: AgentUsage.Problem?, plan: String?, limits: [AgentUsage.Limit]? = nil,
                        fetchedAt: Date? = nil) {
        probing = false
        guard var next = usage else { return }
        let now = Date()
        next.problem = problem
        if let plan { next.plan = plan }
        next.limits = limits ?? next.limits.filter { $0.isOpen(at: now) }
        if let fetchedAt { next.fetchedAt = fetchedAt }
        publish(next)
    }

    private func retryAfterTransportFailure() {
        retry?.invalidate()
        let retry = Timer(timeInterval: ClaudeUsage.transportRetry, repeats: false) { [weak self] _ in
            self?.refresh(force: false)
        }
        RunLoop.main.add(retry, forMode: .common)
        self.retry = retry
    }

    private func publish(_ next: AgentUsage) {
        guard usage != nil, next != usage else { return }
        usage = next
        onChange?()
    }

    // MARK: - The Keychain

    /// Claude Code's saved sign-in, from the login Keychain through `/usr/bin/security` — see
    /// the type's comment for why the tool and not the framework — or from
    /// `~/.claude/.credentials.json`, where Claude Code keeps it on a machine with no Keychain
    /// and where upstream reads it. On `queue`: `security` is a process and a Keychain lookup.
    private static func readCredentials() -> ClaudeUsage.Credentials? {
        if let data = keychainItem(), let credentials = ClaudeUsage.credentials(data) { return credentials }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return (try? Data(contentsOf: file)).flatMap(ClaudeUsage.credentials)
    }

    private static func keychainItem() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-a", NSUserName(), "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Log.error("agents: could not run security: \(error.localizedDescription)")
            return nil
        }
        // A watchdog, for the day an access list changes and `security` waits on a dialog
        // nobody is looking at: the read gives up rather than holding the queue.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    // MARK: - The cache

    private static func loadCache() -> ClaudeUsage.Cache? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= sizeLimit else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ClaudeUsage.Cache.self, from: data)
    }

    private static func saveCache(_ cache: ClaudeUsage.Cache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache), StateDirectory.ensure() else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - The transcripts

    /// Reads what was appended to the transcripts since last time, on `queue`, and publishes
    /// the totals. One scan at a time; a request for another while one runs is dropped, since
    /// the running one will see whatever it would have.
    private func scan() {
        guard !scanning else { return }
        scanning = true
        let started = Date()
        queue.async { [weak self] in
            guard let self else { return }
            let bytes = self.scanTranscripts()
            let stats = self.transcripts.stats
            DispatchQueue.main.async {
                self.scanning = false
                if bytes > 0 {
                    Log.info("agents: read \(bytes >> 10) KB of transcripts in "
                             + String(format: "%.2fs", Date().timeIntervalSince(started)))
                }
                guard var next = self.usage else { return }
                next.tokens = stats
                self.publish(next)
            }
        }
    }

    /// On `queue`. Answers how many bytes were taken in.
    private func scanTranscripts() -> Int {
        guard let walker = FileManager.default.enumerator(at: Self.projectsURL,
                                                          includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                          options: [.skipsHiddenFiles]) else { return 0 }
        var total = 0
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let size = values?.fileSize.map(UInt64.init) else { continue }
            let path = url.path
            // A file that shrank was rewritten, not appended to: read it again from the top.
            // The message ids already counted keep the repeat out of the totals.
            var offset = offsets[path] ?? 0
            if size < offset { offset = 0 }
            guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: offset)
                // Whole lines only, in slices, so a 200 MB transcript is never in memory at once:
                // what a slice ends partway through is read again at the front of the next.
                var carry = Data()
                while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                    carry.append(chunk)
                    let used = transcripts.consume(carry, file: path)
                    offset += UInt64(used)
                    total += used
                    carry = carry.subdata(in: carry.startIndex.advanced(by: used)..<carry.endIndex)
                }
            } catch {
                Log.error("agents: could not read \(url.lastPathComponent): \(error.localizedDescription)")
            }
            offsets[path] = offset
        }
        return total
    }
}
