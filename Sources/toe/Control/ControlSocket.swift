import Darwin
import Foundation
import ToeCore

/// The listening half of `toe query` and `toe dispatch`.
///
/// A Unix domain socket at `~/.local/state/toe/toe.sock`, beside the four journals and the
/// session file, because it is the same kind of thing: state that belongs to this machine's one
/// running toe. The alternative on macOS is a Mach service, which has to be declared in a
/// launchd plist — and toe is as often started by `open Toe.app`, which never goes near launchd,
/// so that channel would exist for some launches and not for others. A socket works however toe
/// was started, and `nc` can talk to it, which has been worth a great deal while building this.
///
/// **Everything here runs on the main thread, deliberately and dangerously.** A request ends in
/// `Coordinator.dispatch`, which writes window frames over Accessibility, and Accessibility is
/// main-thread-only. Handing the socket a background queue would only move the hop somewhere
/// less obvious. The price is that a client which connects and then says nothing is holding the
/// compositor's hand, so nothing here may ever block:
///
///   * every descriptor is non-blocking, and a partial write is finished by a write source
///     rather than by spinning;
///   * a request is capped at 64 KiB, and a connection that has not produced a whole one within
///     two seconds is closed unread;
///   * `SO_NOSIGPIPE` is set on every accepted descriptor, because the default answer to writing
///     down a socket the client has already closed is to kill the process.
///
/// The connection is closed after one reply. That is what lets the reply be pretty-printed JSON
/// with newlines in it: the request is newline-framed, the response is framed by end of file.
final class ControlSocket {

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/toe/toe.sock")

    /// Answers a request with the bytes to send back. Called on the main thread.
    var onRequest: ((ControlRequest) -> Data)?

    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private var connections: [ObjectIdentifier: Connection] = [:]

    /// How long a connection has to produce a whole request.
    private static let requestDeadline: TimeInterval = 2
    /// A request is a line of JSON naming a verb. Anything past this is not one.
    private static let requestLimit = 64 << 10

    var isRunning: Bool { source != nil }

    // MARK: - Lifecycle

    @discardableResult
    func start() -> String? {
        guard source == nil else { return nil }

        let path = Self.url.path
        // `sun_path` is 104 bytes on Darwin, which the state directory is nowhere near — but the
        // check is here rather than assumed, because the failure it prevents is a silent bind to
        // a truncated path.
        guard path.utf8.count < 104 else {
            return "the socket path is too long for a Unix socket: \(path)"
        }

        do {
            try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return "could not make \(Self.url.deletingLastPathComponent().path): \(error.localizedDescription)"
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return "could not open a socket: \(errorText())" }

        // A socket file left behind by a copy that was killed rather than quit. Removing it
        // unconditionally is safe for the reason `AppIdentity.takeOver` is: exactly one toe runs
        // at a time, and it has already waited for the other one to be gone.
        unlink(path)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: 104) { destination in
                strncpy(destination, path, 103)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else {
            let message = "could not bind \(path): \(errorText())"
            close(fd)
            return message
        }

        // After the bind, which is when the file exists. The directory is already 0700, so this
        // is belt and braces — but the socket is the one thing in there that is an *entry point*
        // rather than a record, and it should say so in its own mode.
        chmod(path, 0o600)

        guard listen(fd, 8) == 0 else {
            let message = "could not listen on \(path): \(errorText())"
            close(fd)
            unlink(path)
            return message
        }
        setNonBlocking(fd)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptWaiting() }
        // The descriptor is closed here and nowhere else: cancelling a source is asynchronous,
        // and a descriptor closed before the source has finished with it can be handed to
        // something else in between.
        source.setCancelHandler { close(fd) }
        source.resume()

        self.listener = fd
        self.source = source
        Log.info("cli: listening on \(path)")
        return nil
    }

    func stop() {
        guard let source else { return }
        for connection in connections.values { connection.close() }
        connections.removeAll()
        source.cancel()
        self.source = nil
        listener = -1
        unlink(Self.url.path)
    }

    // MARK: - Accepting

    private func acceptWaiting() {
        // Until EAGAIN: a read source fires once for any number of pending connections, and
        // accepting one per firing would leave the rest waiting on the next client.
        while true {
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }

            // Same user only. The socket is already 0600 inside a 0700 directory, so this is not
            // load-bearing — it is the check that stays true if either of those ever slips.
            var uid = uid_t(), gid = gid_t()
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                Log.error("cli: refused a connection from uid \(uid)")
                close(fd)
                continue
            }

            setNonBlocking(fd)
            // Without this, replying down a socket whose client has already gone away kills toe.
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            let connection = Connection(fd: fd,
                                        limit: Self.requestLimit,
                                        onRequest: { [weak self] data in self?.answer(data) ?? Data() },
                                        onFinish: { [weak self] connection in
                                            self?.connections.removeValue(forKey: ObjectIdentifier(connection))
                                        })
            connections[ObjectIdentifier(connection)] = connection
            connection.start(deadline: Self.requestDeadline)
        }
    }

    /// One request's worth of bytes in, one reply's worth out. Every failure below is answered
    /// rather than dropped: a client that gets nothing back cannot tell a refusal from a toe
    /// that has wedged, and the whole point of a control socket is that the far end can find out
    /// what happened.
    private func answer(_ data: Data) -> Data {
        guard let request = try? ControlCoding.decoder().decode(ControlRequest.self, from: data) else {
            return ControlCoding.line(ControlFailure("that is not a request toe understands"))
        }
        guard request.version <= ControlRequest.currentVersion else {
            return ControlCoding.line(ControlFailure(
                "this request speaks protocol \(request.version) and toe speaks "
                + "\(ControlRequest.currentVersion) — the `toe` on your PATH is newer than the "
                + "one that is running"))
        }
        guard let onRequest else {
            return ControlCoding.line(ControlFailure("toe is not ready for commands yet"))
        }
        return onRequest(request)
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    private func errorText() -> String { String(cString: strerror(errno)) }
}

// MARK: - One client

/// Reads one newline-framed request, writes one reply, closes.
///
/// A class with its own sources rather than a synchronous read and write, because both halves
/// run on the main thread: a 200 KiB reply to `query state` on a busy machine can fill the send
/// buffer, and the honest way to finish it is a write source that resumes when there is room.
private final class Connection {

    private let fd: Int32
    private let limit: Int
    private let onRequest: (Data) -> Data
    private let onFinish: (Connection) -> Void

    private var reader: DispatchSourceRead?
    private var writer: DispatchSourceWrite?
    private var inbox = Data()
    private var outbox = Data()
    private var timeout: DispatchWorkItem?
    private var isClosed = false

    init(fd: Int32, limit: Int, onRequest: @escaping (Data) -> Data,
         onFinish: @escaping (Connection) -> Void) {
        self.fd = fd
        self.limit = limit
        self.onRequest = onRequest
        self.onFinish = onFinish
    }

    func start(deadline: TimeInterval) {
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        reader.setEventHandler { [weak self] in self?.readWaiting() }
        reader.resume()
        self.reader = reader

        // A client that opens a connection and says nothing would otherwise sit here forever
        // holding a descriptor and a place in the accept queue.
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isClosed else { return }
            Log.error("cli: a connection sent nothing within \(Int(deadline))s — closing it")
            self.close()
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline, execute: work)
    }

    private func readWaiting() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let read = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, 4096) }
            if read > 0 {
                inbox.append(contentsOf: buffer[0..<read])
                guard inbox.count <= limit else {
                    reply(ControlCoding.line(ControlFailure("that request is too long")))
                    return
                }
                if let newline = inbox.firstIndex(of: 0x0a) {
                    answer(inbox[inbox.startIndex..<newline])
                    return
                }
                continue
            }
            if read == 0 {
                // End of file with no newline: a client that wrote its request and shut its
                // writing half without a terminator, which is what a plain `printf | nc` does.
                // Answering it is friendlier than insisting on the framing.
                if inbox.isEmpty { close() } else { answer(inbox[...]) }
                return
            }
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            if errno == EINTR { continue }
            close()
            return
        }
    }

    private func answer(_ request: Data.SubSequence) {
        timeout?.cancel()
        timeout = nil
        reader?.cancel()
        reader = nil
        reply(onRequest(Data(request)))
    }

    private func reply(_ data: Data) {
        outbox = data
        flush()
    }

    private func flush() {
        while !outbox.isEmpty {
            let written = outbox.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, outbox.count) }
            if written > 0 {
                outbox.removeFirst(written)
                continue
            }
            if written < 0, errno == EINTR { continue }
            if written < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                waitForRoom()
                return
            }
            // The client has gone. Nothing to report to and nothing to do about it.
            close()
            return
        }
        close()
    }

    private func waitForRoom() {
        guard writer == nil else { return }
        let writer = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: .main)
        writer.setEventHandler { [weak self] in
            guard let self else { return }
            self.writer?.cancel()
            self.writer = nil
            self.flush()
        }
        writer.resume()
        self.writer = writer
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        timeout?.cancel()
        timeout = nil
        // The descriptor is closed by whichever source still holds it, for the reason the
        // listener's is: cancellation is asynchronous. With neither source left it is closed
        // here.
        if let reader {
            reader.setCancelHandler { [fd] in Darwin.close(fd) }
            reader.cancel()
            self.reader = nil
            self.writer?.cancel()
            self.writer = nil
        } else if let writer {
            writer.setCancelHandler { [fd] in Darwin.close(fd) }
            writer.cancel()
            self.writer = nil
        } else {
            Darwin.close(fd)
        }
        onFinish(self)
    }
}
