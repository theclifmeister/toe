import Foundation
import ToeCore

/// Minimal assertion harness. XCTest is not available without Xcode, and the layout engine
/// is pure geometry, so a plain executable is all this needs.
final class Harness {
    private(set) var failures: [String] = []
    private var current = ""
    private var passed = 0

    func test(_ name: String, _ body: (Harness) throws -> Void) {
        current = name
        do {
            try body(self)
        } catch {
            failures.append("\(name): threw \(error)")
        }
    }

    func expect(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
        if condition { passed += 1 } else { failures.append("\(current):\(line) — \(message())") }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ what: String, line: Int = #line) {
        if a == b { passed += 1 } else { failures.append("\(current):\(line) — \(what): got \(a), want \(b)") }
    }

    func equalBox(_ a: Box?, _ b: Box, _ what: String, line: Int = #line) {
        guard let a else {
            failures.append("\(current):\(line) — \(what): got nil, want \(b.pretty)")
            return
        }
        let same = abs(a.x - b.x) < 0.51 && abs(a.y - b.y) < 0.51 && abs(a.w - b.w) < 0.51 && abs(a.h - b.h) < 0.51
        if same { passed += 1 } else { failures.append("\(current):\(line) — \(what): got \(a.pretty), want \(b.pretty)") }
    }

    func report() -> Int32 {
        if failures.isEmpty {
            print("\u{001B}[32m✓\u{001B}[0m \(passed) assertions passed")
            return 0
        }
        print("\u{001B}[31m✗\u{001B}[0m \(failures.count) failure(s), \(passed) passed\n")
        for f in failures { print("  • \(f)") }
        return 1
    }
}

extension Box {
    var pretty: String {
        String(format: "(%.0f, %.0f, %.0f × %.0f)", x, y, w, h)
    }
}

func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box {
    Box(x: x, y: y, w: w, h: h)
}
