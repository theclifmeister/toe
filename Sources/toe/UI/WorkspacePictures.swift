import AppKit
import ToeCore

/// The pictures of workspaces as they were when the user last left them, for the slide to
/// bring in without photographing them again.
///
/// The slide's second picture — the workspace arriving — was the expensive one: the real switch
/// had to be made, the apps given a beat to paint, and only then could it be taken, which put
/// some 260 ms between the fingers committing and the first frame of motion (measured on a
/// 14" MacBook, v0.29.0: outgoing picture 75 ms, switched 135, incoming picture 260). The
/// picture taken on the way *out* of a workspace is the picture of it, though, and a workspace
/// mostly looks as it did when it was left — so it is kept here, and on the way back in it is
/// what slides, with the live screen replacing it when the panel comes down. The rule for when
/// it may be used is `WorkspaceSlide.Fingerprint`'s: same windows, same frames, same border, or
/// it is not used and the slide takes its picture the slow way as before. Content may be stale;
/// shape may not.
///
/// The cost is memory, and it is the same sum `ScreenSnapshot.wallpaperScale` does: a picture
/// is the display's pixels at 4 bytes each, ~31 MB on a 14" MacBook and ~30 MB on a 5K display,
/// and these are full resolution because the incoming picture comes to rest showing the new
/// workspace until the panel drops, where a soft one would snap sharp. `limit` pictures per
/// display is the whole of the footprint — three is the workspace just left and the two either
/// side of it, which is where a swipe can go — and `RecentCache` decides which three.
final class WorkspacePictures {

    /// How many pictures each display keeps.
    static let limit = 3

    struct Picture {
        var image: CGImage
        /// The windows on it, as the mask that lets them slide over the wallpaper — grown for
        /// the border on the focused one, since the picture has the ring in it.
        var cutouts: [WorkspaceSlide.Cutout]
        var fingerprint: WorkspaceSlide.Fingerprint
        /// The area it is a picture of. A display change makes every picture the wrong size,
        /// and `Coordinator.screensChanged` forgets them for that reason; this is the check
        /// that catches a rect that changed without one.
        var area: Box
        /// What the desktop picture was when this was taken, as `ScreenSnapshot` keeps it: the
        /// picture is masked to its windows, so the wallpaper in it is only seen when the
        /// wallpaper capture has failed and the whole picture slides — but then it is seen.
        var desktopPicture: URL?
        var taken: Date
    }

    private var pictures: [CGDirectDisplayID: RecentCache<Int, Picture>] = [:]

    /// Keeps `picture` as the picture of `workspace` on `display`, in place of any earlier one.
    func keep(_ picture: Picture, of workspace: Int, on display: CGDirectDisplayID) {
        pictures[display, default: RecentCache(limit: Self.limit)].insert(picture, for: workspace)
    }

    /// The picture of `workspace` on `display`, if there is one and it still fits: same
    /// `fingerprint`, same `area`, same desktop picture. Anything else is nil, and a picture
    /// that no longer fits is dropped rather than kept for a fingerprint that will not recur.
    func picture(of workspace: Int, on display: CGDirectDisplayID,
                 fingerprint: WorkspaceSlide.Fingerprint, area: Box, desktopPicture: URL?) -> Picture? {
        guard let picture = pictures[display]?.lookup(workspace) else { return nil }
        guard picture.fingerprint == fingerprint, picture.area == area,
              picture.desktopPicture == desktopPicture else {
            pictures[display]?.remove(workspace)
            return nil
        }
        return picture
    }

    /// Forgets every picture, for a display change or a reload: the rects and the border have
    /// both possibly changed, and a fingerprint does not carry the border's colour.
    func forgetAll() {
        pictures.removeAll()
    }
}
