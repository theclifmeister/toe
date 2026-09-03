import Foundation

/// Watches the config file for changes and calls back on the main queue.
///
/// The parent directory is watched as well as the file itself: most editors save atomically
/// by writing a temporary file and renaming it over the original, which silently kills a
/// watch bound only to the original file descriptor.
///
/// Also pointed at `~/.config/toe/themes`, where the target is a directory rather than a file
/// and an entry appearing in it is a write to the directory itself — so there the parent watch
/// is switched off, because the parent is `~/.config/toe` and would fire this watcher on every
/// save of `toe.toml` as well. That directory's own existence is watched by the config watcher
/// already, which is what lets a themes folder created after toe started still be picked up.
final class ConfigWatcher {

    private let url: URL
    private let watchesParent: Bool
    private let events: DispatchSource.FileSystemEvent
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?

    var onChange: (() -> Void)?

    /// - Parameter events: what counts as a change. `.attrib` is in the default because the
    ///   config file is also checked for its permissions, and it is deliberately *out* of the one
    ///   the theme watches pass: a palette's timestamps are not its colours, and asking to hear
    ///   about them means hearing about toe's own read of the file it just reloaded for.
    init(url: URL, watchesParent: Bool = true,
         events: DispatchSource.FileSystemEvent = [.write, .extend, .attrib, .delete, .rename]) {
        self.url = url
        self.watchesParent = watchesParent
        self.events = events
    }

    func start() {
        if watchesParent { watchDirectory() }
        watchFile()
    }

    func stop() {
        debounce?.cancel()
        fileSource?.cancel(); fileSource = nil
        directorySource?.cancel(); directorySource = nil
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: events,
            queue: .main)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.scheduleReload()
            if flags.contains(.delete) || flags.contains(.rename) {
                // The file we had open is gone; re-bind to whatever replaced it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.watchFile()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileSource = source
    }

    private func watchDirectory() {
        let directory = url.deletingLastPathComponent()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if self.fileSource == nil { self.watchFile() }
            self.scheduleReload()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directorySource = source
    }

    private func scheduleReload() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
