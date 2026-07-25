import Foundation

// What the REMOTE app has turned on. A drag can only become wheel events if
// the app asked for mouse tracking AND can read the encoding we'd send, and
// neither can be asked of the local terminal: SwiftTerm keeps the encoding
// private, and a snapshot resets our terminal's state anyway. hop's server
// tracks both across the whole session and reports them with every snapshot,
// so they are seeded there and kept current by watching the stream for the
// same sequences the server watches.
//
// Pure, and tested, because the failure is silent in the worst way: get it
// wrong and a drag falls through to keys, which at a claude prompt recalls
// previous PROMPTS — a scroll gesture that rewrites what you were typing.
struct RemoteMouseState {
    private(set) var reporting = false
    private(set) var sgr = false
    private var tail = ""

    /// Both halves matter. Mouse tracking alone means the app wants mouse
    /// input; without SGR it expects the legacy encoding, which caps
    /// coordinates at 223 and which we don't send.
    var takesWheel: Bool { reporting && sgr }

    /// From a snapshot, which carries the server's view of the whole session —
    /// including modes set long before the replay window starts.
    mutating func seed(reporting: Bool, sgr: Bool) {
        self.reporting = reporting
        self.sgr = sgr
        tail = ""
    }

    /// From live output, so the flags follow the app: claude starting inside a
    /// shell session, or exiting and handing the screen back.
    mutating func note(_ chunk: String) {
        guard chunk.contains("[?") || !tail.isEmpty else { return }
        let text = tail + chunk
        for match in Self.modePattern.matches(
            in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let params = Range(match.range(at: 1), in: text),
                  let action = Range(match.range(at: 2), in: text) else { continue }
            let on = text[action] == "h"
            for param in text[params].split(separator: ";") {
                switch param {
                case "1000", "1002", "1003": reporting = on
                case "1006": sgr = on
                default: break
                }
            }
        }
        // Carry a tail only when the chunk actually ends mid-sequence — an ESC
        // with no terminator after it. Carrying one unconditionally would make
        // every later chunk fail the cheap prefilter and run the regex, on the
        // hot path that paints the screen.
        if let esc = text.lastIndex(of: "\u{1b}"),
           text.distance(from: esc, to: text.endIndex) < Self.maxPartial,
           !text[esc...].contains(where: { $0 == "h" || $0 == "l" }) {
            tail = String(text[esc...])
        } else {
            tail = ""
        }
    }

    private static let maxPartial = 24
    private static let modePattern = try! NSRegularExpression(
        pattern: "\u{1b}\\[\\?([0-9;]+)([hl])")
}

/// The wheel events for `rows` of finger travel, aimed at the middle of the
/// screen — an app that routes scrolling by pane would otherwise get every
/// notch at the edge. Built by hand rather than through SwiftTerm's encoder,
/// which reads our own terminal's mouse state; the app's is the one that
/// matters. Same shape as hop's web client sends.
func wheelSequence(rows: Int, cols: Int, screenRows: Int, cap: Int = 40) -> String {
    guard rows != 0 else { return "" }
    let code = rows > 0 ? 64 : 65               // dragging down looks backwards
    let col = max(1, cols / 2), row = max(1, screenRows / 2)
    return String(repeating: "\u{1b}[<\(code);\(col);\(row)M",
                  count: min(abs(rows), cap))
}
