import Foundation
import os

/// Diagnostics for the two things that go wrong in practice: a missing Accessibility grant,
/// and a config that did not load. Read them with:
///
///     log stream --predicate 'subsystem == "com.clifmeister.toe"' --level info
enum Log {
    private static let logger = Logger(subsystem: "com.clifmeister.toe", category: "toe")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if ProcessInfo.processInfo.environment["TOE_VERBOSE"] != nil { FileHandle.standardError.write(Data("toe: \(message)\n".utf8)) }
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        FileHandle.standardError.write(Data("toe: \(message)\n".utf8))
    }
}
