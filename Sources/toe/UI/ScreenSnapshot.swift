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
    func refresh() {
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
            }
        }
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
        config.sourceRect = CGRect(x: area.x - frame.x, y: area.y - frame.y, width: area.w, height: area.h)
        config.width = Int((area.w * scale).rounded())
        config.height = Int((area.h * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best

        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
            DispatchQueue.main.async {
                if image == nil {
                    Log.error("slide: capture failed: \(error?.localizedDescription ?? "no image")")
                }
                completion(image)
            }
        }
    }
}
