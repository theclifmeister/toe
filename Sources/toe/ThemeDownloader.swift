import Foundation
import ToeCore

/// Fetches one theme from Omarchy into `~/.config/toe/themes/<name>/`.
///
/// Everything here is written on the assumption that the bytes are hostile, because they came off
/// the network and they are being written next to a config file that runs shell commands. Three
/// rules do the work, and all three are whitelists rather than checks for bad input:
///
///  - the directory is `Slug.make`'s output, so it is one path component and cannot be anything
///    else;
///  - every file name comes from the catalogue and has been through `Catalogue.isSafeFileName`
///    *and* the image-extension filter, and is joined onto the folder rather than trusted as a
///    path;
///  - the palette is parsed before anything is moved into place, so a theme that would not have
///    loaded never becomes a theme you have.
///
/// It assembles into a temporary directory and moves the finished thing into place, so a download
/// that fails halfway leaves nothing behind — the failure mode being avoided is a half-theme that
/// looks installed and is missing the picture the cycle is pointing at.
enum ThemeDownloader {

    /// No single background in Omarchy is past 4 MB. This is not a policy about how big a
    /// wallpaper may be; it is a ceiling so a redirect to something enormous cannot fill a disk —
    /// or, since `BoundedGET` cancels the transfer at the limit rather than measuring the body
    /// once it has all arrived, the memory it would have gone through on the way (#130).
    private static let fileLimit = 64 << 20
    private static let paletteLimit = 64 << 10
    /// How often a transfer in flight says how much of it has arrived.
    ///
    /// Every report rebuilds the menu's tree and redraws the panel, so this is a rate rather than
    /// a resolution: six a second is smooth to the eye and nowhere near the cost of a keystroke,
    /// which does the same work. It is also why `Coordinator.refreshMenu` stopped re-reading the
    /// themes directory — at this rate that was twelve directory listings a second for a list
    /// that cannot change while a download is running.
    private static let progressInterval: TimeInterval = 1.0 / 6
    private static let timeout: TimeInterval = 60

    enum Failure: Error, CustomStringConvertible {
        case network(String)
        case badPalette(String)
        case couldNotWrite(String)

        var description: String {
            switch self {
            case .network(let what):      return what
            case .badPalette(let why):    return "its colours would not parse — \(why)"
            case .couldNotWrite(let why): return why
            }
        }
    }

    /// Downloads `theme` and calls back on the main queue with where it landed.
    ///
    /// `progress` reports `ThemeDownload` — ToeCore's own type — rather than a shape of this
    /// file's. It used to be a local struct carrying the theme's *name* as well, for the menu bar
    /// strip that built `⟳ Gruvbox 3/6` out of it; the strip is gone, the row that fills instead
    /// is identified by slug, and what was left was two numbers being copied into a type that
    /// already held two numbers. This reports the one that has the arithmetic on it.
    static func fetch(_ theme: RemoteTheme,
                      into directory: URL,
                      progress: @escaping (ThemeDownload) -> Void,
                      completion: @escaping (Result<Void, Failure>) -> Void) {
        // At the door, and not trusted from the catalogue that produced it: `RemoteTheme` is also
        // read back out of a cached `catalogue.json`, and a file in the config directory is
        // something the user — or a script — may have edited.
        guard let slug = Slug(theme.slug) else {
            return completion(.failure(.couldNotWrite("'\(theme.slug)' is not a theme name")))
        }

        DispatchQueue.global(qos: .utility).async {
            let result = fetchSynchronously(theme, slug: slug.value, into: directory, progress: progress)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func fetchSynchronously(_ theme: RemoteTheme, slug: String, into directory: URL,
                                           progress: @escaping (ThemeDownload) -> Void)
    -> Result<Void, Failure> {
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("toe-theme-\(slug)-\(UUID().uuidString)")
        let pictures = staging.appendingPathComponent("backgrounds")
        defer { try? FileManager.default.removeItem(at: staging) }

        do {
            try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure(.couldNotWrite(error.localizedDescription))
        }

        let total = theme.backgrounds.count
        let bytesTotal = theme.bytes
        // Bytes of the pictures finished with. Advanced by the catalogue's figure for each
        // picture rather than by what actually arrived, so that it lands exactly on `bytesTotal`
        // at the end however much the two disagreed on the way — the bar reaching its end is
        // worth more than it being faithful to a size somebody else's repository reported.
        var landed = 0

        func report(_ fetching: Int, _ bytesDone: Int) {
            DispatchQueue.main.async {
                progress(ThemeDownload(slug: slug, fetching: fetching, total: total,
                                       bytesDone: bytesDone, bytesTotal: bytesTotal))
            }
        }

        // The palette first: if it will not parse there is no point fetching nine megabytes of
        // photographs to go with it. `fetching: 0` says so — no picture is in flight yet, so the
        // row keeps showing what the theme costs until there is a count to put there instead.
        report(0, 0)
        let paletteData: Data
        switch get(Upstream.file(theme: slug, "colors.toml"), limit: paletteLimit) {
        case .success(let data): paletteData = data
        case .failure(let why):  return .failure(why)
        }
        guard let text = String(data: paletteData, encoding: .utf8) else {
            return .failure(.badPalette("it is not text"))
        }
        do {
            _ = try Palette.parse(text)
        } catch {
            return .failure(.badPalette("\(error)"))
        }
        do {
            try paletteData.write(to: staging.appendingPathComponent("colors.toml"))
        } catch {
            return .failure(.couldNotWrite(error.localizedDescription))
        }

        for (index, picture) in theme.backgrounds.enumerated() {
            // `index + 1`, and reported before the fetch rather than after: the number names the
            // picture being fetched, so it reads as "picture 1 of 2" while that is what is
            // happening, and ends on 2 of 2 rather than stopping at 1.
            report(index + 1, landed)

            // Checked again here rather than trusted from the catalogue. The catalogue is a cache
            // — it is a file on disk that something else could have written — and this is the
            // moment a name becomes a path.
            //
            // A skipped picture still takes its share of the bar on the way past. It is work
            // accounted for, and the alternative is a bar that can never reach its end because
            // one name in the listing was not a name.
            guard Catalogue.isSafeFileName(picture.name),
                  !Backgrounds.isUpstreamBranding(picture.name),
                  Backgrounds.list([picture.name]).count == 1 else {
                landed += picture.bytes
                continue
            }

            switch get(Upstream.file(theme: slug, "backgrounds/\(picture.name)"), limit: fileLimit,
                       // Capped at what the catalogue said this picture weighs, so a transfer
                       // that comes in heavier than advertised cannot push the bar past the
                       // pictures still to come.
                       received: { received in report(index + 1, landed + min(received, picture.bytes)) }) {
            case .success(let data):
                // `appendingPathComponent` on a name that has been through both filters above:
                // no separator, no leading dot, a known image extension.
                try? data.write(to: pictures.appendingPathComponent(picture.name))
            case .failure(let why):
                // One missing picture is not worth losing the theme over — the palette is the
                // part that changes what you see.
                Log.error("themes: \(theme.slug)/\(picture.name): \(why)")
            }
            landed += picture.bytes
        }

        // The last word, and the reason the bar reaches its end rather than stopping just short
        // of it. Every other report is sent before or during a transfer, so without this one the
        // final state the row ever draws is however much of the last picture had arrived when it
        // was last asked — which is what "it stops at the last end" looked like.
        report(total, bytesTotal)

        // Into place in one move, so a theme is either there whole or not there.
        let destination = directory.appendingPathComponent(slug)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: destination.path) {
                // Re-downloading an existing theme replaces it. Anything you put in its
                // backgrounds folder yourself goes with it, which is why the menu only offers
                // this for themes you do not already have.
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            return .failure(.couldNotWrite(error.localizedDescription))
        }
        return .success(())
    }

    /// One synchronous GET, on a queue where blocking is the point.
    ///
    /// - Parameter received: called with the bytes taken in so far, every `progressInterval`,
    ///   while the transfer is still running. This is why the wait below is a loop rather than the
    ///   single `semaphore.wait` it used to be: a four-megabyte photograph is the longest thing
    ///   toe does, and a bar that could only move when a whole file landed sat still for the
    ///   whole of it. Polling `countOfBytesReceived` rather than a delegate or KVO because this
    ///   function is already blocking on a semaphore with a deadline — the loop is the wait it
    ///   was doing anyway, cut into slices. (`BoundedGET` *is* a delegate, but for the limit, not
    ///   for progress: it sees every chunk, and the bar does not need to.)
    private static func get(_ url: URL, limit: Int,
                            received: ((Int) -> Void)? = nil) -> Result<Data, Failure> {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Data, Failure> = .failure(.network("no answer"))

        // The limit, the host and the status are all `BoundedGET`'s to check, and it checks them
        // when the headers arrive rather than after the body has — see there for why that is not
        // the same thing.
        let task = BoundedGET.task(request, limit: limit) { result in
            outcome = result.mapError { .network($0.description) }
            semaphore.signal()
        }
        task.resume()

        // The same deadline as before, waited out in slices. Reporting between them rather than
        // after the wait returns, because by then the transfer is over and there is nothing left
        // to say about it.
        //
        // `timeoutInterval` is an idle interval — the time since the last byte — not a total, so
        // a response that trickles outlives this deadline with the task still running. The break
        // used to leave it running: the transfer went on buffering after the theme had been
        // reported as failed, and its completion handler wrote `outcome` from the session's queue
        // after the function that declared it had returned (#130). Now the task is cancelled, and
        // the loop waits once more for the signal that says the outcome is settled.
        let deadline = Date().addingTimeInterval(timeout + 5)
        while semaphore.wait(timeout: .now() + progressInterval) == .timedOut {
            if Date() >= deadline {
                task.cancel()
                // Without a deadline of its own, deliberately. `cancel()` is asynchronous — it
                // asks, and the answer is a `didCompleteWithError` on the delegate queue some
                // time later — but it is also a promise: a task that has been cancelled completes
                // exactly once, with `NSURLErrorCancelled` if nothing else got there first. If
                // the transfer finished between the slice above and the cancel, the signal is
                // already pending and this returns at once; if not, it returns when the
                // cancellation lands. Either way `outcome` has been written by the time it does,
                // which a bounded wait here could not say.
                semaphore.wait()
                break
            }
            received?(Int(task.countOfBytesReceived))
        }
        return outcome
    }
}
