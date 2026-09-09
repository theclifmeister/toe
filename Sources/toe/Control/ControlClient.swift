import Darwin
import Foundation
import ToeCore

/// The `toe` you type: connect, say one thing, print what comes back, exit.
///
/// This runs before `NSApplication` exists and never creates one. It is the same binary as the
/// window manager and shares its code, but not its life: no Accessibility, no hotkeys, no menu
/// bar, no `Coordinator` — a few milliseconds and a file descriptor.
///
/// Blocking calls throughout, which is the opposite of `ControlSocket` and right for the same
/// reason it is wrong there. Nothing else is happening in this process; there is no run loop to
/// starve and no window to leave un-drawn. The one thing guarded is the wait, so a wedged agent
/// cannot leave a shell hanging.
enum ControlClient {

    /// How long to wait for a reply. Generous, because a reply can be behind a synchronous
    /// Accessibility write for every window on a workspace, and short enough that a toe which is
    /// never going to answer says so while somebody is still watching.
    private static let replyTimeout: TimeInterval = 10

    /// - Returns: the process's exit status. 0 worked, 1 reached toe and was refused, 2 never
    ///   got that far — the distinction a script needs to tell a typo from a "no".
    static func run(_ invocation: CLIInvocation) -> Int32 {
        switch invocation.kind {
        case .agent:
            return 0   // never reached: main.swift only calls this for the other cases

        case .help(let text):
            print(text)
            return 0

        case .error(let message):
            complain(message)
            return 2

        case .skill(let action):
            return skill(action)

        case .request(var request):
            if invocation.readsStdin {
                request.commands = (request.commands ?? []) + linesFromStandardInput()
                guard !(request.commands ?? []).isEmpty else {
                    complain("nothing on stdin to dispatch")
                    return 2
                }
            }
            return send(request)
        }
    }

    // MARK: - The skill file

    /// Done here rather than sent to the agent. Writing a file needs a file system, not a window
    /// manager — so `toe skill install` works on a machine where toe has never been started, and
    /// the day the socket is switched off in the config this is still the way in.
    private static func skill(_ action: CLIInvocation.Skill) -> Int32 {
        switch action {
        case .print:
            print(SkillStore.text)
            return 0

        case .status:
            return emit(SkillStore.state())

        case .install:
            switch SkillStore.install() {
            case .success(let report):
                return emit(report)
            case .failure(let refusal):
                complain(refusal.description)
                return 1
            }

        case .remove:
            switch SkillStore.remove() {
            case .success(let report):
                return emit(report)
            case .failure(let refusal):
                complain(refusal.description)
                return 1
            }
        }
    }

    private static func emit<T: Encodable>(_ value: T) -> Int32 {
        FileHandle.standardOutput.write(ControlCoding.line(ControlSuccess(value)))
        return 0
    }

    // MARK: - The socket

    private static func send(_ request: ControlRequest) -> Int32 {
        guard let payload = try? JSONEncoder().encode(request) else {
            complain("could not encode that request")
            return 2
        }

        let path = ControlSocket.url.path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            complain("could not open a socket: \(errorText())")
            return 2
        }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, path, 103) }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else {
            // The two ways this fails are the two ways toe can be absent, and they deserve the
            // same sentence: no socket file at all (never started, or shut down cleanly), and a
            // socket file nothing is listening on (killed). Neither is worth explaining to
            // somebody who only wanted to move a window.
            complain(errno == ENOENT || errno == ECONNREFUSED
                     ? "toe is not running"
                     : "could not reach toe at \(path): \(errorText())")
            return 1
        }

        // The deadline is the socket's own, so a toe that accepts the connection and then wedges
        // cannot hold a shell open indefinitely.
        var deadline = timeval(tv_sec: Int(replyTimeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var line = payload
        line.append(0x0a)
        var sent = 0
        while sent < line.count {
            let written = line.withUnsafeBytes {
                write(fd, $0.baseAddress!.advanced(by: sent), line.count - sent)
            }
            guard written > 0 else {
                complain("toe closed the connection before hearing the request")
                return 1
            }
            sent += written
        }
        // Says "that is all of it". The reply is framed by end of file rather than by a newline,
        // because it is pretty-printed and full of them.
        shutdown(fd, SHUT_WR)

        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let read = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, 8192) }
            if read > 0 { reply.append(contentsOf: buffer[0..<read]); continue }
            if read == 0 { break }
            if errno == EINTR { continue }
            complain(errno == EAGAIN || errno == EWOULDBLOCK
                     ? "toe did not answer within \(Int(replyTimeout))s"
                     : "lost the connection to toe: \(errorText())")
            return 1
        }

        guard !reply.isEmpty else {
            complain("toe answered with nothing")
            return 1
        }

        // A refusal is a sentence on stderr and a non-zero exit, not JSON on stdout: a shell
        // pipeline should see an empty stdout when nothing worked, and a person should see the
        // reason without reading JSON. Everything that *did* work goes to stdout whole, exactly
        // as toe wrote it — pretty-printed, in declaration order, ready to be piped into `jq`.
        if let failure = try? ControlCoding.decoder().decode(ControlFailure.self, from: reply),
           !failure.ok {
            complain(failure.error)
            return 1
        }
        FileHandle.standardOutput.write(reply)
        return 0
    }

    // MARK: - Odds and ends

    /// One command line per line, blank ones dropped and `#` comments ignored — so a file of
    /// commands can be kept, annotated, and piped in.
    private static func linesFromStandardInput() -> [String] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func complain(_ message: String) {
        FileHandle.standardError.write(Data("toe: \(message)\n".utf8))
    }

    private static func errorText() -> String { String(cString: strerror(errno)) }
}
