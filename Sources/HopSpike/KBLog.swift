import UIKit

// The keyboard-frame instrument (PLAN 11). Jian: switching keyboards
// (system <-> Wispr <-> emoji) sometimes leaves the grid too small for the
// space actually left. The settle verifier didn't cure it, so before
// guessing again, RECORD the sequence: every keyboard frame, every fit,
// every settle verdict, with the view bounds beside them. The ring is
// surfaced in Account -> Copy diagnostics, so one bad switch on the real
// phone becomes a pasteable trace naming which layer went stale — the
// keyboard's frame, SwiftUI's avoidance (view bounds), or SwiftTerm's grid.
@MainActor
enum KBLog {
    private(set) static var lines: [String] = []
    // 240: a single screen transition emits a dozen kbFrame/fit/wake lines,
    // and the trace must survive the WALK to Copy diagnostics — an 80-line
    // ring evicted the keystroke being diagnosed on the way there.
    private static let cap = 240
    private static let epoch = Date()

    static func record(_ line: String) {
        let t = Int(Date().timeIntervalSince(epoch) * 1000) % 600_000
        lines.append("t+\(t)ms \(line)")
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
    }

    /// The last events, newest last — the tail is what a bad switch just did.
    static func dump(last n: Int = 120) -> String {
        lines.suffix(n).joined(separator: "\n")
    }
}
