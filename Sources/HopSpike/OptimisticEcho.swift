import Foundation

// Local echo (PLAN 25): typed characters render NOW and the server's echo is
// consumed when it arrives, instead of every keystroke waiting a full tunnel
// round-trip (100-300ms on cellular) to appear.
//
// This is a PORT of hay/apps/web/src/utils/optimisticEcho.ts, deliberately
// faithful — that file's comments record deterministically-reproduced
// failure modes (fast "alal" rendering as "llllllalalal"; Claude's composer
// eating typed text on repaint) and the model that survives them:
//   - only PRINTABLE input is echoed (escapes/controls pass straight through
//     to the wire and are never predicted);
//   - a chunk carrying non-SGR control sequences is a REDRAW — pending drops
//     and the chunk passes untouched, because the repaint is the truth;
//   - echoes are consumed in order with a foreign-char stop, so program
//     output is never swallowed out of order;
//   - pending expires (800ms) and two consecutive mismatches clear it.
struct OptimisticEcho {
    private var pending = ""
    private var lastEchoAt: TimeInterval = 0
    private var mismatchCount = 0
    private let maxPendingMs: TimeInterval
    private let now: () -> TimeInterval

    init(maxPendingMs: TimeInterval = 800,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 * 1000 }) {
        self.maxPendingMs = maxPendingMs
        self.now = now
    }

    var pendingText: String { pending }

    private static func isPrintable(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1 else { return false }
        return v >= 0x20 && v <= 0x7e
    }

    /// Strip escape sequences and non-printables; what remains is what a
    /// local echo may honestly predict.
    private static func filterPrintable(_ data: String) -> String {
        var result = ""
        let chars = Array(data)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\u{1b}" {
                i += 1
                if i < chars.count, chars[i] == "[" {
                    i += 1
                    while i < chars.count {
                        let code = chars[i].unicodeScalars.first?.value ?? 0
                        if code >= 0x40, code <= 0x7e { i += 1; break }
                        i += 1
                    }
                } else {
                    i += 1
                }
                continue
            }
            if isPrintable(ch) { result.append(ch) }
            i += 1
        }
        return result
    }

    /// Returns what to render immediately (empty when disabled or nothing
    /// printable). The caller sends the ORIGINAL data to the wire either way.
    mutating func onInput(_ data: String, enabled: Bool) -> String {
        guard enabled else { return "" }
        let filtered = Self.filterPrintable(data)
        guard !filtered.isEmpty else { return "" }
        pending += filtered
        lastEchoAt = now()
        return filtered
    }

    /// Filters a server chunk against pending echoes. Returns what to feed.
    mutating func reconcileOutput(_ data: String) -> String {
        guard !pending.isEmpty else { return data }

        if now() - lastEchoAt > maxPendingMs {
            pending = ""
            mismatchCount = 0
            return data
        }

        // TUI guard: cursor moves / erases / OSC mean REDRAW, not echo.
        let chars = Array(data)
        var scan = 0
        var complex = false
        while scan < chars.count {
            let c = chars[scan]
            if c == "\u{1b}" {
                let next = scan + 1 < chars.count ? chars[scan + 1] : " "
                if next == "[" {
                    var j = scan + 2
                    while j < chars.count {
                        let code = chars[j].unicodeScalars.first?.value ?? 0
                        j += 1
                        if code >= 0x40, code <= 0x7e {
                            if chars[j - 1] != "m" { complex = true }
                            break
                        }
                    }
                    scan = j
                    continue
                }
                complex = true      // OSC / other escapes: treat as redraw
                break
            }
            scan += 1
        }
        if complex {
            pending = ""
            mismatchCount = 0
            return data
        }

        // Consume echoed copies of pending chars from the printable stream,
        // preserving control sequences verbatim; stop at the first foreign
        // printable so real output is never swallowed out of order.
        var out = ""
        var i = 0
        var consumed = 0
        var sawForeign = false
        let pendingChars = Array(pending)
        while i < chars.count {
            let ch = chars[i]
            if ch == "\u{1b}" {
                var j = i + 1
                if j < chars.count, chars[j] == "[" {
                    j += 1
                    while j < chars.count {
                        let code = chars[j].unicodeScalars.first?.value ?? 0
                        j += 1
                        if code >= 0x40, code <= 0x7e { break }
                    }
                } else {
                    j += 1
                }
                out += String(chars[i..<j])
                i = j
                continue
            }
            if !sawForeign, consumed < pendingChars.count, Self.isPrintable(ch),
               ch == pendingChars[consumed] {
                consumed += 1
                i += 1
                continue
            }
            if !sawForeign, consumed < pendingChars.count, Self.isPrintable(ch) {
                sawForeign = true
            }
            out.append(ch)
            i += 1
        }

        if consumed > 0 {
            pending = String(pendingChars[consumed...])
            mismatchCount = 0
            return out
        }

        mismatchCount += 1
        if mismatchCount >= 2 {
            pending = ""
            mismatchCount = 0
        }
        return data
    }

    mutating func reset() {
        pending = ""
        mismatchCount = 0
    }
}
