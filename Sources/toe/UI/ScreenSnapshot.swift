import AppKit
import ScreenCaptureKit
import ToeCore

/// A picture of one display's usable area, for `SlideOverlay`.
///
/// This is the one thing in toe behind a second permission. Accessibility moves windows; it
/// cannot see them, and neither can `CGWindowListCopyWindowInfo`, which `WindowStack` reads for
/// geometry alone. A picture of the screen is Screen Recording, whichever API takes it — and
/// since macOS 15 an app holding that grant is reminded of it now and then in the menu bar. So
/// nothing here runs unless `animations.slide_on_swipe` is on, the grant is checked with
/// `CGPreflightScreenCaptureAccess` before ScreenCaptureKit is so much as asked what is on
/// screen (asking is enough to make it prompt), and the pictures live exactly as long as the
/// slide that needs them.
///
/// The grant is TCC's state, not toe's: nothing to journal, nothing to give back.
final class ScreenSnapshot {

    /// What `SCShareableContent` last said. Kept, because enumerating every window on the
    /// system costs tens of milliseconds and a swipe should cost one capture, not that first.
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]
    /// toe itself, for the picture that must not contain toe's own panel.
    private var toe: SCRunningApplication?
    /// The Dock, which is the process that draws the desktop picture — `Wallpaper-` is one of
    /// its windows, at the desktop level — and so the one to ask for a picture of the wallpaper
    /// alone.
    private var dock: SCRunningApplication?
    private var requested = false
    /// The picture of the desktop behind each display, kept between swipes.
    ///
    /// The wallpaper is the one subject that does not change while a swipe happens — that is the
    /// whole reason it is a picture of its own — so taking it again per swipe bought nothing and
    /// cost the slide its budget: `beginSlide` waits for *both* pictures before the panel can go
    /// up, and two concurrent captures compete for the same encoder. Learned at v0.20.0, where
    /// the slide was a coin flip because of it — measured at 2-4 ms for a hit against 27-60 ms
    /// for the capture it replaces, which is the difference between racing the deadline with one
    /// picture and racing it with two. Keyed on the rect it was taken for *and* on the
    /// desktop picture it was taken of, so a resolution change or a new wallpaper misses rather
    /// than showing the wrong thing — see `CachedWallpaper`.
    ///
    /// The cost is memory, and it is worth naming: one picture per attached display, held for as
    /// long as that display is attached. `SlideOverlay.hide` drops its three pictures precisely
    /// so that they are not held, so the reasoning has to be met head on — **peak** memory is
    /// unchanged, because during a slide this is one of those three anyway; what grows is the
    /// steady state, between swipes. `wallpaperScale` is what keeps that number small enough to
    /// be worth it: 7.4 MB per display on a 5120×1440 screen rather than 29.5. Bounded by the
    /// number of displays and by nothing the user does — but it is still why nothing else here
    /// is cached, and why a fourth picture should not be.
    private var wallpapers: [CGDirectDisplayID: CachedWallpaper] = [:]

    /// A cached desktop picture, with everything a swipe has to agree with before it may use it.
    private struct CachedWallpaper {
        var area: Box
        var frame: Box
        /// What `NSWorkspace` said the desktop picture was when this was taken.
        ///
        /// The wallpaper is written by toe on a theme change (`Wallpaper.set`) *and* by the user
        /// in System Settings, and a cache with no answer for the second would slide the previous
        /// picture under the windows until the next display change. One rule covers both: the hit
        /// is checked against the live URL, which is the same cheap read-back `Wallpaper.apply`
        /// already leans on. Deliberately not a notification from `Wallpaper` as well — that
        /// would catch the subset this already catches, and be the copy that drifts. Not
        /// airtight, though: a dynamic or shuffling desktop
        /// picture changes what is on screen without changing its URL, and that one slide is
        /// wrong. It is a picture of the desktop behind moving windows for a third of a second,
        /// and worth less than a capture per swipe.
        var picture: URL?
        var image: CGImage
    }

    /// How much of the wallpaper's resolution is worth taking, as a fraction of the display's.
    ///
    /// The only picture here that may be shrunk, and the reason is what each one has to survive
    /// being looked at *while standing still*:
    ///
    /// - The outgoing picture is shown static over the live screen for `slidePanelLatency`
    ///   before anything moves, and it is a photograph of exactly what is already there. At full
    ///   resolution it is invisible; at anything less the whole screen would go soft for a frame
    ///   and then slide, which is the "flash before the slide" that `SlideOverlay.begin`'s
    ///   `CATransaction.flush` exists to prevent. Full resolution, always.
    /// - The incoming picture comes to rest showing the new workspace, and the live screen only
    ///   replaces it when the panel goes down. A soft one would snap sharp at the end. Same.
    /// - The wallpaper never stands in for anything sharp. It is a backdrop, behind window
    ///   pictures that are moving over it, for one `slide_duration`, and half of it is under a
    ///   window at any moment. `CALayer.contentsGravity = .resize` stretches it back up for
    ///   free (see `SlideOverlay`), and bilinear upscaling of a desktop picture at this size is
    ///   not something the eye has time to find.
    ///
    /// A half in each direction is a quarter of the pixels: on a 5120×1440 display that is 29.5
    /// MB down to 7.4 MB, and it is the one of the three that is *kept* between swipes, so this
    /// is the number that decides toe's steady-state footprint. It also makes the capture itself
    /// cheaper, which the deadline gets the benefit of. Lower it further if the footprint matters
    /// more than the backdrop does; the wallpaper is the only thing that gets worse.
    private static let wallpaperScale = 0.5

    /// Whether Screen Recording is granted. Read on every swipe rather than once: a grant given
    /// in System Settings while toe runs is worth noticing without a relaunch, where it lands.
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// A display this can take pictures of.
    func knows(display id: CGDirectDisplayID) -> Bool { displays[id] != nil }

    /// Asks for the grant, once per process. The first call shows the system prompt and returns
    /// false straight away — the grant is given in System Settings, and like Accessibility it
    /// is keyed to the code signature, so a rebuild without `make dev-cert` loses it. A later
    /// call, after a refusal, returns false silently; the user's answer is not nagged about.
    func requestOnce() {
        guard !requested else { return }
        requested = true
        if !CGRequestScreenCaptureAccess() {
            Log.error("slide: Screen Recording is not granted — allow toe in System Settings › "
                      + "Privacy & Security › Screen & System Audio Recording, then relaunch")
        }
    }

    /// Learns what is on screen. Asynchronous, and a failure keeps whatever was known before:
    /// a display list that is stale by one screen is still right about the others.
    ///
    /// `then` runs on the main queue once the list is in, and only then — it is where the caller
    /// warms the capture path (`warm`), which cannot be done before there is a display to point
    /// it at. It does not run if the grant is missing or the enumeration failed, because in
    /// neither case is there anything to warm.
    func refresh(then: (() -> Void)? = nil) {
        guard Self.isGranted else { return }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let content else {
                    Log.error("slide: could not list the displays: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                self.displays = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
                self.toe = content.applications.first { $0.processID == getpid() }
                self.dock = content.applications.first { $0.bundleIdentifier == "com.apple.dock" }
                Log.info("slide: \(self.displays.count) display(s) can be pictured")
                then?()
            }
        }
    }

    /// Builds the capture pipeline before a swipe needs it, and fills the wallpaper cache doing so.
    ///
    /// ScreenCaptureKit's first `captureImage` in a process is hundreds of milliseconds — it is
    /// spinning up capture infrastructure, not photographing a screen — which is more than the
    /// whole slide budget and is why the first swipe of every run never slid. `refresh` warmed
    /// the display *list* and nothing else; the comment on `slidePictureDeadline` has always
    /// claimed a warm session, and this is what finally makes that true.
    ///
    /// The warm-up is a real wallpaper capture rather than a throwaway, so the cost buys the
    /// cache as well. Areas are `Monitor.usable` / `Monitor.frame`, exactly as a swipe will ask
    /// for them, or the cache would miss on the very first swipe it was taken for.
    func warm(_ areas: [(id: CGDirectDisplayID, area: Box, frame: Box)]) {
        guard Self.isGranted else { return }
        let started = Date()
        for a in areas where displays[a.id] != nil {
            capture(display: a.id, area: a.area, frame: a.frame, of: .wallpaper) { image in
                // The size is here rather than left to arithmetic: it is the one place to see
                // that `wallpaperScale` is being applied, and what it is costing in memory.
                Log.info("slide: display \(a.id) warm after"
                         + " \(Int(Date().timeIntervalSince(started) * 1000)) ms"
                         + (image.map { " — wallpaper \($0.width)×\($0.height),"
                                        + " \($0.width * $0.height * 4 / 1_048_576) MB" }
                            ?? " — no wallpaper picture"))
            }
        }
    }

    /// The desktop picture `NSWorkspace` currently has on `id`, or nil if that display is not
    /// one AppKit is listing — which is not a failure worth logging, only a cache that misses.
    private static func desktopPicture(of id: CGDirectDisplayID) -> URL? {
        NSScreen.screens.first { $0.displayID == id }
            .flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    }

    /// Drops the cached desktop pictures, for a display change: the rects they were keyed on
    /// have just stopped meaning anything, so this is freeing memory rather than correcting an
    /// answer — `CachedWallpaper` would have missed on its own. A *new wallpaper* needs nothing
    /// called; that is the URL check's job, and calling something here as well is the second
    /// place the rule could drift from.
    func forgetWallpapers() {
        wallpapers.removeAll()
    }

    /// What a picture is of.
    enum Subject {
        /// Everything on screen, toe's border included — the outgoing picture is what the user
        /// was looking at.
        case everything
        /// Everything but toe's own windows — the incoming picture is taken with the slide's
        /// panel already covering the screen, and a picture of the panel showing the last
        /// picture is a hall of mirrors.
        case everythingButToe
        /// The desktop picture alone: the Dock's windows and nothing else. What the windows
        /// slide over. (Finder's desktop icons are a Finder window, so they are not in it and
        /// sit the slide out.)
        case wallpaper
    }

    /// A picture of `area` — in AX coordinates, on the display whose frame is `frame` — delivered
    /// on the main queue, or nil for any failure. A nil is the caller's cue to switch without
    /// the slide; nothing here retries, because the user is mid-gesture.
    func capture(display id: CGDirectDisplayID, area: Box, frame: Box, of subject: Subject,
                 completion: @escaping (CGImage?) -> Void) {
        guard let display = displays[id] else { completion(nil); return }

        // A cache hit answers on the spot rather than on the next turn of the main queue. That is
        // the point of it — the slide is racing a deadline measured in a few frames — and it is
        // safe because every caller is already on the main queue and treats this as a callback
        // that may have run by the time `capture` returns; see `beginSlide`'s `proceed`.
        if case .wallpaper = subject, let have = wallpapers[id], have.area == area, have.frame == frame,
           have.picture == Self.desktopPicture(of: id) {
            completion(have.image)
            return
        }

        // Two shapes of filter, and they differ in more than the list: a filter that *excludes*
        // applications starts from the whole display, wallpaper included, and a filter that
        // *includes* them starts from nothing. Neither can be made transparent — the window
        // server composites every capture onto an opaque backstop, and asking to leave that out
        // is refused — which is why the wallpaper is a picture of its own rather than a hole in
        // the others; see `WorkspaceSlide.cutouts`.
        let filter: SCContentFilter
        switch subject {
        case .everything:
            filter = SCContentFilter(display: display, excludingWindows: [])
        case .everythingButToe:
            filter = SCContentFilter(display: display, excludingApplications: [toe].compactMap { $0 },
                                     exceptingWindows: [])
        case .wallpaper:
            guard let dock else { completion(nil); return }
            filter = SCContentFilter(display: display, including: [dock], exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        // `sourceRect` is in the display's own logical points, origin at its top-left — the AX
        // box less the display's AX origin, since both are y-down. `width` / `height` are pixels
        // and default to 1920 × 1080 whatever the rect, so they are set from the rect and the
        // display's own scale, or a Retina picture comes back at half its resolution.
        let scale = CGFloat(filter.pointPixelScale)
        // `sourceRect` still names the whole region — it is what is photographed, not how big
        // the photograph is. Only the pixel count asked for shrinks, and only for the wallpaper.
        var wanted = 1.0
        if case .wallpaper = subject { wanted = Self.wallpaperScale }
        config.sourceRect = CGRect(x: area.x - frame.x, y: area.y - frame.y, width: area.w, height: area.h)
        config.width = max(1, Int((area.w * scale * wanted).rounded()))
        config.height = max(1, Int((area.h * scale * wanted).rounded()))
        config.showsCursor = false
        config.captureResolution = .best

        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { [weak self] image, error in
            DispatchQueue.main.async {
                if image == nil {
                    Log.error("slide: capture failed: \(error?.localizedDescription ?? "no image")")
                }
                if case .wallpaper = subject, let self, let image {
                    // Read *after* the capture, not before: a wallpaper written in between would
                    // otherwise be cached under the old URL and never noticed.
                    self.wallpapers[id] = CachedWallpaper(area: area, frame: frame,
                                                          picture: Self.desktopPicture(of: id),
                                                          image: image)
                }
                completion(image)
            }
        }
    }
}
