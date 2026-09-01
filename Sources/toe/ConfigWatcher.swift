import Foundation

/// Watches the config file for changes and calls back on the main queue.
///
/// The parent directory is watched as well as the file itself: most editors save atomically
/// by writing a temporary file and renaming it over the original, which silently kills a
/// watch bound only to the original file descriptor.
final class ConfigWatcher {

    private let url: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?

    var onChange: (() -> Void)?

    init(url: URL) { self.url = url }

    func start() {
        watchDirectory()
        watchFile()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
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
